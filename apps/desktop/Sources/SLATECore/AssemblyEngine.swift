import Foundation
import SLATESharedTypes

public struct AssemblyGenerationOptions: Sendable, Equatable {
    public var name: String?
    public var sceneFilter: String?
    public var selectedSubjectIds: [String]
    public var selectedTopicTags: [String]
    public var preferredClipOrder: [String]

    public init(
        name: String? = nil,
        sceneFilter: String? = nil,
        selectedSubjectIds: [String] = [],
        selectedTopicTags: [String] = [],
        preferredClipOrder: [String] = []
    ) {
        self.name = name
        self.sceneFilter = sceneFilter
        self.selectedSubjectIds = selectedSubjectIds
        self.selectedTopicTags = selectedTopicTags
        self.preferredClipOrder = preferredClipOrder
    }
}

public struct AssemblyEngine: Sendable {
    public init() {}

    /// Chooses the best angle/take for a multi-camera group using the same narrative scoring as assembly build.
    public func selectBestClipForMultiCamGroup(_ clips: [Clip]) -> Clip? {
        guard let first = clips.first,
              let narrative = first.narrativeMeta else {
            return nil
        }
        let scene = narrative.sceneNumber
        let setup = narrative.shotCode
        return selectNarrativeClip(
            from: clips,
            previousSceneLastWordCluster: [],
            sceneMedianWordCount: medianWordCount(for: clips),
            scene: scene,
            setup: setup
        )?.clip
    }

    public func buildAssembly(
        project: Project,
        clips: [Clip],
        options: AssemblyGenerationOptions = .init(),
        assemblyId: String = UUID().uuidString,
        version: Int = 1
    ) -> SLATESharedTypes.Assembly {
        let assemblyClips: [AssemblyClip]
        switch project.mode {
        case .narrative:
            assemblyClips = buildNarrativeAssembly(clips: clips, options: options)
        case .documentary:
            assemblyClips = buildDocumentaryAssembly(clips: clips, options: options)
        }

        let resolvedClips: [AssemblyClip]
        if assemblyClips.isEmpty, let fallback = clips.first {
            let sceneLabel: String
            switch project.mode {
            case .narrative:
                if let narrative = fallback.narrativeMeta {
                    sceneLabel = "\(narrative.sceneNumber)\(narrative.shotCode)"
                } else {
                    sceneLabel = "Narrative Clip"
                }
            case .documentary:
                sceneLabel = documentaryLabel(for: fallback)
            }
            resolvedClips = [
                makeAssemblyClip(
                    clipId: fallback.id,
                    inPoint: 0,
                    outPoint: fallback.duration,
                    role: project.mode == .narrative ? .primary : documentaryRole(for: fallback),
                    sceneLabel: sceneLabel,
                    rank: 0,
                    reason: "Selected: fallback clip to keep non-empty rough cut for \(sceneLabel)"
                )
            ]
        } else {
            resolvedClips = assemblyClips
        }

        let name = resolvedAssemblyName(project: project, options: options)
        return SLATESharedTypes.Assembly(
            id: assemblyId,
            projectId: project.id,
            name: name,
            mode: project.mode,
            clips: resolvedClips,
            version: version
        )
    }

    private func buildNarrativeAssembly(clips: [Clip], options: AssemblyGenerationOptions) -> [AssemblyClip] {
        let candidates = clips.filter { clip in
            guard let narrative = clip.narrativeMeta else { return false }
            guard clip.projectMode == .narrative else { return false }
            if let sceneFilter = options.sceneFilter, narrative.sceneNumber != sceneFilter {
                return false
            }
            return true
        }

        let scenes = Dictionary(grouping: candidates) { $0.narrativeMeta?.sceneNumber ?? "Unknown Scene" }
        let orderedScenes = scenes.keys.sorted(by: naturalLessThan)

        var orderedAssemblyClips: [AssemblyClip] = []
        var previousSceneLastWordCluster: Set<String> = []
        for scene in orderedScenes {
            let sceneClips = scenes[scene] ?? []
            let setupGroups = Dictionary(grouping: sceneClips) { $0.narrativeMeta?.shotCode ?? "ZZZ" }
            let orderedSetups = setupGroups.keys.sorted(by: naturalLessThan)
            let sceneMedianWordCount = medianWordCount(for: sceneClips)
            var selectedInScene: [Clip] = []

            for setup in orderedSetups {
                guard let selection = selectNarrativeClip(
                    from: setupGroups[setup] ?? [],
                    previousSceneLastWordCluster: previousSceneLastWordCluster,
                    sceneMedianWordCount: sceneMedianWordCount,
                    scene: scene,
                    setup: setup
                ) else {
                    continue
                }

                selectedInScene.append(selection.clip)
                orderedAssemblyClips.append(
                    makeAssemblyClip(
                        clipId: selection.clip.id,
                        inPoint: 0,
                        outPoint: selection.clip.duration,
                        role: .primary,
                        sceneLabel: "\(scene)\(setup)",
                        rank: orderedAssemblyClips.count,
                        reason: selection.reason
                    )
                )
            }

            if let sceneTail = selectedInScene.last {
                previousSceneLastWordCluster = lastWordCluster(for: sceneTail)
            }
        }

        let orderedWithOverrides = applyPreferredClipOrder(options.preferredClipOrder, to: orderedAssemblyClips)
        validateNarrativeSceneOrder(orderedWithOverrides, clipLookup: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) }))
        return orderedWithOverrides
    }

    private func buildDocumentaryAssembly(clips: [Clip], options: AssemblyGenerationOptions) -> [AssemblyClip] {
        let filtered = clips.filter { clip in
            guard let documentary = clip.documentaryMeta else { return false }
            guard clip.projectMode == .documentary else { return false }

            if !options.selectedSubjectIds.isEmpty && !options.selectedSubjectIds.contains(documentary.subjectId) {
                return false
            }

            if !options.selectedTopicTags.isEmpty {
                let tags = Set(documentary.topicTags)
                return !tags.isDisjoint(with: options.selectedTopicTags)
            }

            return true
        }

        let circled = filtered.filter { $0.reviewStatus == .circled }
        let source = circled.isEmpty ? filtered : circled
        let preferredOrder = options.preferredClipOrder

        guard !source.isEmpty else {
            return []
        }

        let wordSets = Dictionary(uniqueKeysWithValues: source.map { ($0.id, transcriptWordSet(for: $0)) })
        let clusters = buildDocumentaryClusters(clips: source, wordSets: wordSets)
        let orderedClips = clusters.flatMap { cluster in
            cluster.sorted { lhs, rhs in
                let lhsDensity = lhs.aiScores?.contentDensity ?? lhs.aiScores?.composite ?? 0
                let rhsDensity = rhs.aiScores?.contentDensity ?? rhs.aiScores?.composite ?? 0
                if lhsDensity != rhsDensity {
                    return lhsDensity > rhsDensity
                }
                return lhs.ingestedAt < rhs.ingestedAt
            }
        }

        let assembled = orderedClips.enumerated().map { index, clip in
            let trim = breathingRoomTrim(for: clip.duration)
            let density = clip.aiScores?.contentDensity ?? clip.aiScores?.composite ?? 0
            let transcriptSummary = summarizeTranscript(for: clip)
            let reason = String(
                format: "Selected: content density %.1f — '%@'",
                density,
                transcriptSummary
            )
            return makeAssemblyClip(
                clipId: clip.id,
                inPoint: trim.inPoint,
                outPoint: trim.outPoint,
                role: documentaryRole(for: clip),
                sceneLabel: documentaryLabel(for: clip),
                rank: index,
                reason: reason
            )
        }
        return applyPreferredClipOrder(preferredOrder, to: assembled)
    }

    private func buildDocumentaryClusters(clips: [Clip], wordSets: [String: Set<String>]) -> [[Clip]] {
        var remaining = Set(clips.map(\.id))
        var clusters: [[Clip]] = []
        let clipById = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })

        while let seedId = remaining.first {
            var clusterIds: Set<String> = [seedId]
            var changed = true
            while changed {
                changed = false
                for candidateId in remaining where !clusterIds.contains(candidateId) {
                    guard let candidateWords = wordSets[candidateId] else { continue }
                    let belongsInCluster = clusterIds.contains { clusterId in
                        let clusterWords = wordSets[clusterId] ?? []
                        return cosineSimilarity(words1: candidateWords, words2: clusterWords) > 0.35
                    }
                    if belongsInCluster {
                        clusterIds.insert(candidateId)
                        changed = true
                    }
                }
            }

            let cluster = clusterIds.compactMap { clipById[$0] }
            clusters.append(cluster)
            remaining.subtract(clusterIds)
        }

        return clusters.sorted { lhs, rhs in
            let lhsTop = lhs.map { $0.aiScores?.contentDensity ?? $0.aiScores?.composite ?? 0 }.max() ?? 0
            let rhsTop = rhs.map { $0.aiScores?.contentDensity ?? $0.aiScores?.composite ?? 0 }.max() ?? 0
            if lhsTop != rhsTop {
                return lhsTop > rhsTop
            }
            let lhsLabel = documentaryLabel(for: lhs.first ?? lhs[0])
            let rhsLabel = documentaryLabel(for: rhs.first ?? rhs[0])
            return naturalLessThan(lhsLabel, rhsLabel)
        }
    }

    private func selectNarrativeClip(
        from clips: [Clip],
        previousSceneLastWordCluster: Set<String>,
        sceneMedianWordCount: Int,
        scene: String,
        setup: String
    ) -> (clip: Clip, reason: String)? {
        let circled = clips.filter { $0.reviewStatus == .circled }
        let source = circled.isEmpty ? clips : circled
        guard !source.isEmpty else { return nil }

        let ranked = source.sorted { lhs, rhs in
            let lhsScore = narrativeSelectionScore(for: lhs, previousSceneLastWordCluster: previousSceneLastWordCluster)
            let rhsScore = narrativeSelectionScore(for: rhs, previousSceneLastWordCluster: previousSceneLastWordCluster)
            let delta = abs(lhsScore - rhsScore)
            if delta <= 3 {
                let lhsDistance = abs(transcriptWordCount(for: lhs) - sceneMedianWordCount)
                let rhsDistance = abs(transcriptWordCount(for: rhs) - sceneMedianWordCount)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
            }
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            let lhsTake = lhs.narrativeMeta?.takeNumber ?? 0
            let rhsTake = rhs.narrativeMeta?.takeNumber ?? 0
            return lhsTake < rhsTake
        }
        guard let selected = ranked.first else { return nil }

        let performance = selected.aiScores?.performance ?? 0
        let reason = String(
            format: "Selected: highest performance score (%.1f) across %d takes for scene %@/setup %@",
            performance,
            source.count,
            scene,
            setup
        )
        return (selected, reason)
    }

    private func narrativeSelectionScore(for clip: Clip, previousSceneLastWordCluster: Set<String>) -> Double {
        let aiScores = clip.aiScores
        let composite = aiScores?.composite ?? 0
        let performance = aiScores?.performance ?? 0
        let audio = aiScores?.audio ?? 0
        let continuityBonus = continuityBonus(for: clip, previousSceneLastWordCluster: previousSceneLastWordCluster)
        return (composite * 0.40) + (performance * 0.35) + (audio * 0.15) + (continuityBonus * 0.10)
    }

    private func continuityBonus(for clip: Clip, previousSceneLastWordCluster: Set<String>) -> Double {
        guard !previousSceneLastWordCluster.isEmpty else {
            return 0
        }
        let words = transcriptWordSet(for: clip)
        return words.isDisjoint(with: previousSceneLastWordCluster) ? 0 : 1
    }

    private func documentaryRole(for clip: Clip) -> AssemblyClipRole {
        if clip.audioTracks.contains(where: { [.boom, .lav, .mix].contains($0.role) }) {
            return .interview
        }
        if clip.documentaryMeta?.interviewerOffscreen == false {
            return .interview
        }
        return .broll
    }

    private func documentaryLabel(for clip: Clip) -> String {
        guard let documentary = clip.documentaryMeta else {
            return "Documentary Clip"
        }

        if let topic = documentary.topicTags.first, !topic.isEmpty {
            return "\(documentary.subjectName) • \(topic)"
        }
        return "\(documentary.subjectName) • \(documentary.sessionLabel)"
    }

    private func resolvedAssemblyName(project: Project, options: AssemblyGenerationOptions) -> String {
        if let name = options.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }

        switch project.mode {
        case .narrative:
            if let scene = options.sceneFilter, !scene.isEmpty {
                return "\(project.name) Scene \(scene) Assembly"
            }
            return "\(project.name) Narrative Assembly"
        case .documentary:
            if !options.selectedTopicTags.isEmpty {
                return "\(project.name) Topic Assembly"
            }
            if !options.selectedSubjectIds.isEmpty {
                return "\(project.name) Subject Assembly"
            }
            return "\(project.name) Documentary Assembly"
        }
    }

    private func applyPreferredClipOrder(_ preferredOrder: [String], to assemblyClips: [AssemblyClip]) -> [AssemblyClip] {
        guard !preferredOrder.isEmpty else {
            return assemblyClips
        }

        let indexed = Dictionary(uniqueKeysWithValues: assemblyClips.map { ($0.clipId, $0) })
        let preferred = preferredOrder.compactMap { indexed[$0] }
        let remaining = assemblyClips.filter { !preferredOrder.contains($0.clipId) }
        return preferred + remaining
    }

    private func naturalLessThan(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }

    private func makeAssemblyClip(
        clipId: String,
        inPoint: Double,
        outPoint: Double,
        role: AssemblyClipRole,
        sceneLabel: String,
        rank: Int,
        reason: String,
        isSelected: Bool = true
    ) -> AssemblyClip {
        let baseClip = AssemblyClip(
            clipId: clipId,
            inPoint: inPoint,
            outPoint: outPoint,
            role: role,
            sceneLabel: sceneLabel
        )

        let payload: [String: Any] = [
            "clipId": clipId,
            "inPoint": inPoint,
            "outPoint": outPoint,
            "role": role.rawValue,
            "sceneLabel": sceneLabel,
            "rank": rank,
            "reason": reason,
            "isSelected": isSelected
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let decoded = try? JSONDecoder().decode(AssemblyClip.self, from: data)
        else {
            return baseClip
        }
        return decoded
    }

    private func transcriptText(for clip: Clip) -> String {
        let annotationText = clip.annotations
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.body)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !annotationText.isEmpty {
            return annotationText
        }

        let aiReasoning = (clip.aiScores?.reasoning ?? [])
            .map(\.message)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return aiReasoning
    }

    private func transcriptTokens(for clip: Clip) -> [String] {
        let rawText = transcriptText(for: clip)
            .lowercased()
        let scalars = rawText.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(scalars)
        return normalized
            .split(separator: " ")
            .map(String.init)
            .filter { token in
                token.count > 1 && !stopwords.contains(token)
            }
    }

    private func transcriptWordSet(for clip: Clip) -> Set<String> {
        Set(transcriptTokens(for: clip))
    }

    private func transcriptWordCount(for clip: Clip) -> Int {
        transcriptTokens(for: clip).count
    }

    private func summarizeTranscript(for clip: Clip) -> String {
        let text = transcriptText(for: clip)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return documentaryLabel(for: clip).lowercased()
        }
        if text.count <= 72 {
            return text
        }
        let index = text.index(text.startIndex, offsetBy: 72)
        return "\(text[..<index])..."
    }

    private func medianWordCount(for clips: [Clip]) -> Int {
        let counts = clips.map(transcriptWordCount).sorted()
        guard !counts.isEmpty else {
            return 0
        }
        let mid = counts.count / 2
        if counts.count.isMultiple(of: 2) {
            return Int((Double(counts[mid - 1] + counts[mid])) / 2.0)
        }
        return counts[mid]
    }

    private func lastWordCluster(for clip: Clip) -> Set<String> {
        let tokens = transcriptTokens(for: clip)
        guard !tokens.isEmpty else {
            return []
        }
        let clusterSize = min(6, tokens.count)
        return Set(tokens.suffix(clusterSize))
    }

    private func validateNarrativeSceneOrder(_ assemblyClips: [AssemblyClip], clipLookup: [String: Clip]) {
        var previousScene: String?
        for assemblyClip in assemblyClips {
            guard let scene = clipLookup[assemblyClip.clipId]?.narrativeMeta?.sceneNumber else {
                continue
            }
            if let previousScene, naturalLessThan(scene, previousScene) {
                print("AssemblyEngine warning: Scene out of order detected (\(previousScene) -> \(scene)). Pickups may have been reordered.")
            }
            previousScene = scene
        }
    }

    private func breathingRoomTrim(for duration: Double) -> (inPoint: Double, outPoint: Double) {
        guard duration > 3 else {
            return (0, duration)
        }
        let inPoint = 0.5
        let outPoint = max(inPoint, duration - 0.5)
        return (inPoint, outPoint)
    }

    private func cosineSimilarity(words1: Set<String>, words2: Set<String>) -> Double {
        let union = words1.union(words2)
        guard !union.isEmpty else {
            return 0
        }
        let intersection = words1.intersection(words2)
        return Double(intersection.count) / Double(union.count)
    }

    private let stopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
        "had", "has", "have", "he", "her", "him", "his", "i", "in", "is", "it",
        "its", "of", "on", "or", "she", "that", "the", "their", "them", "they",
        "this", "to", "was", "we", "were", "with", "you", "your"
    ]
}
