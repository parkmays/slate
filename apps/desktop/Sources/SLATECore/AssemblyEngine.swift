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

    public func buildAssembly(
        project: Project,
        clips: [Clip],
        options: AssemblyGenerationOptions = .init(),
        assemblyId: String = UUID().uuidString,
        version: Int = 1
    ) -> Assembly {
        let assemblyClips: [AssemblyClip]
        switch project.mode {
        case .narrative:
            assemblyClips = buildNarrativeAssembly(clips: clips, options: options)
        case .documentary:
            assemblyClips = buildDocumentaryAssembly(clips: clips, options: options)
        }

        let name = resolvedAssemblyName(project: project, options: options)
        return Assembly(
            id: assemblyId,
            projectId: project.id,
            name: name,
            mode: project.mode,
            clips: assemblyClips,
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
        for scene in orderedScenes {
            let setupGroups = Dictionary(grouping: scenes[scene] ?? []) { $0.narrativeMeta?.shotCode ?? "ZZZ" }
            let orderedSetups = setupGroups.keys.sorted(by: naturalLessThan)

            for setup in orderedSetups {
                guard let selectedClip = selectNarrativeClip(from: setupGroups[setup] ?? []) else {
                    continue
                }

                orderedAssemblyClips.append(
                    AssemblyClip(
                        clipId: selectedClip.id,
                        inPoint: 0,
                        outPoint: selectedClip.duration,
                        role: .primary,
                        sceneLabel: "\(scene)\(setup)"
                    )
                )
            }
        }

        return applyPreferredClipOrder(options.preferredClipOrder, to: orderedAssemblyClips)
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
        let subjectOrder = options.selectedSubjectIds
        let preferredOrder = options.preferredClipOrder

        let sorted = source.sorted { lhs, rhs in
            if !preferredOrder.isEmpty {
                let lhsIndex = preferredOrder.firstIndex(of: lhs.id) ?? .max
                let rhsIndex = preferredOrder.firstIndex(of: rhs.id) ?? .max
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
            }

            let lhsSubject = lhs.documentaryMeta
            let rhsSubject = rhs.documentaryMeta
            let lhsSubjectIndex = subjectOrder.firstIndex(of: lhsSubject?.subjectId ?? "") ?? .max
            let rhsSubjectIndex = subjectOrder.firstIndex(of: rhsSubject?.subjectId ?? "") ?? .max
            if lhsSubjectIndex != rhsSubjectIndex {
                return lhsSubjectIndex < rhsSubjectIndex
            }

            if (lhsSubject?.subjectName ?? "") != (rhsSubject?.subjectName ?? "") {
                return naturalLessThan(lhsSubject?.subjectName ?? "", rhsSubject?.subjectName ?? "")
            }

            let lhsDensity = lhs.aiScores?.contentDensity ?? lhs.aiScores?.composite ?? 0
            let rhsDensity = rhs.aiScores?.contentDensity ?? rhs.aiScores?.composite ?? 0
            if lhsDensity != rhsDensity {
                return lhsDensity > rhsDensity
            }

            return lhs.ingestedAt < rhs.ingestedAt
        }

        return sorted.map { clip in
            AssemblyClip(
                clipId: clip.id,
                inPoint: 0,
                outPoint: clip.duration,
                role: documentaryRole(for: clip),
                sceneLabel: documentaryLabel(for: clip)
            )
        }
    }

    private func selectNarrativeClip(from clips: [Clip]) -> Clip? {
        let circled = clips.filter { $0.reviewStatus == .circled }
        let source = circled.isEmpty ? clips : circled

        return source.max { lhs, rhs in
            let lhsScore = qualityScore(for: lhs)
            let rhsScore = qualityScore(for: rhs)
            if lhsScore == rhsScore {
                let lhsTake = lhs.narrativeMeta?.takeNumber ?? 0
                let rhsTake = rhs.narrativeMeta?.takeNumber ?? 0
                return lhsTake > rhsTake
            }
            return lhsScore < rhsScore
        }
    }

    private func qualityScore(for clip: Clip) -> Double {
        let reviewWeight: Double
        switch clip.reviewStatus {
        case .circled:
            reviewWeight = 200
        case .flagged:
            reviewWeight = 100
        case .unreviewed:
            reviewWeight = 50
        case .deprioritized:
            reviewWeight = 0
        case .x:
            reviewWeight = -50
        }
        return reviewWeight + (clip.aiScores?.composite ?? 0)
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
}
