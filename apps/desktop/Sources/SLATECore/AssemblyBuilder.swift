import Foundation
import SLATESharedTypes

struct AssemblyBuilder {
    static func build(project: Project, mode: ProjectMode, clips: [Clip]) async -> Assembly {
        switch mode {
        case .narrative:
            return await buildNarrativeAssembly(project: project, clips: clips)
        case .documentary:
            return await buildDocumentaryAssembly(project: project, clips: clips)
        }
    }
    
    private static func buildNarrativeAssembly(project: Project, clips: [Clip]) async -> Assembly {
        // Group clips by scene -> setup
        let grouped = Dictionary(grouping: clips) { clip in
            clip.narrativeMeta?.sceneNumber ?? "Unknown"
        }.mapValues { clips in
            Dictionary(grouping: clips) { clip in
                clip.narrativeMeta?.setupName ?? "Unknown"
            }
        }
        
        var items: [AssemblyItem] = []
        var totalDuration: Double = 0
        var gapCount = 0
        var autoSelectedCount = 0
        
        // Sort scenes numerically
        let sortedScenes = grouped.keys.sorted { scene1, scene2 in
            let num1 = Int(scene1.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
            let num2 = Int(scene2.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
            return (num1 ?? 0) < (num2 ?? 0)
        }
        
        for scene in sortedScenes {
            let setups = grouped[scene] ?? [:]
            
            // Sort setups alphabetically
            let sortedSetups = setups.keys.sorted()
            
            for setup in sortedSetups {
                guard let setupClips = setups[setup], !setupClips.isEmpty else { continue }
                
                // Select best clip: circled > highest score > flagged
                let selectedClip = selectBestClip(from: setupClips)
                
                if let clip = selectedClip {
                    let item = AssemblyItem(
                        id: UUID().uuidString,
                        clip: clip,
                        sceneName: scene,
                        setupName: setup,
                        isAutoSelected: clip.reviewStatus != .circled,
                        isGap: false,
                        sortOrder: items.count
                    )
                    items.append(item)
                    totalDuration += clip.duration
                    
                    if clip.reviewStatus != .circled {
                        autoSelectedCount += 1
                    }
                } else {
                    // Create gap item
                    let gapClip = Clip(
                        projectId: project.id,
                        checksum: "",
                        sourcePath: "",
                        sourceSize: 0,
                        sourceFormat: .proRes422HQ,
                        sourceFps: 24.0,
                        sourceTimecodeStart: "00:00:00:00",
                        duration: 3.0, // 3 second gap
                        proxyPath: nil,
                        proxyStatus: .pending,
                        proxyChecksum: nil,
                        narrativeMeta: NarrativeMeta(
                            sceneNumber: scene,
                            setupName: setup,
                            takeNumber: 0,
                            cameraId: "GAP"
                        ),
                        documentaryMeta: nil,
                        audioTracks: [],
                        syncResult: .unsynced,
                        syncedAudioPath: nil,
                        aiScores: nil,
                        transcriptId: nil,
                        aiProcessingStatus: .pending,
                        reviewStatus: .unreviewed,
                        annotations: [],
                        approvalStatus: .pending,
                        approvedBy: nil,
                        approvedAt: nil,
                        ingestedAt: ISO8601DateFormatter().string(from: Date()),
                        updatedAt: ISO8601DateFormatter().string(from: Date()),
                        projectMode: .narrative
                    )
                    
                    let gapItem = AssemblyItem(
                        id: UUID().uuidString,
                        clip: gapClip,
                        sceneName: scene,
                        setupName: setup,
                        isAutoSelected: false,
                        isGap: true,
                        sortOrder: items.count
                    )
                    items.append(gapItem)
                    totalDuration += 3.0
                    gapCount += 1
                }
            }
        }
        
        return Assembly(
            id: UUID().uuidString,
            projectId: project.id,
            mode: mode,
            items: items,
            totalDuration: totalDuration,
            gapCount: gapCount,
            autoSelectedCount: autoSelectedCount,
            createdAt: Date()
        )
    }
    
    private static func buildDocumentaryAssembly(project: Project, clips: [Clip]) async -> Assembly {
        // Group clips by subject
        let grouped = Dictionary(grouping: clips) { clip in
            clip.documentaryMeta?.subjectName ?? "Unknown"
        }
        
        var items: [AssemblyItem] = []
        var totalDuration: Double = 0
        var gapCount = 0
        var autoSelectedCount = 0
        
        let sortedSubjects = grouped.keys.sorted()
        
        for subject in sortedSubjects {
            guard let subjectClips = grouped[subject] else { continue }
            
            // Group by topic tag
            let topicGroups = Dictionary(grouping: subjectClips) { clip in
                clip.documentaryMeta?.topicTag ?? "General"
            }
            
            for (topic, clips) in topicGroups {
                // Sort by AI score (composite) within each topic
                let sortedClips = clips.sorted { clip1, clip2 in
                    let score1 = clip1.aiScores?.composite ?? 0
                    let score2 = clip2.aiScores?.composite ?? 0
                    return score1 > score2
                }
                
                // Include circled + flagged, skip x + deprioritized
                let filteredClips = sortedClips.filter { clip in
                    clip.reviewStatus != .x && clip.reviewStatus != .deprioritized
                }
                
                for clip in filteredClips {
                    let item = AssemblyItem(
                        id: UUID().uuidString,
                        clip: clip,
                        sceneName: subject,
                        setupName: topic,
                        isAutoSelected: clip.reviewStatus != .circled,
                        isGap: false,
                        sortOrder: items.count
                    )
                    items.append(item)
                    totalDuration += clip.duration
                    
                    if clip.reviewStatus != .circled {
                        autoSelectedCount += 1
                    }
                }
            }
        }
        
        return Assembly(
            id: UUID().uuidString,
            projectId: project.id,
            mode: mode,
            items: items,
            totalDuration: totalDuration,
            gapCount: gapCount,
            autoSelectedCount: autoSelectedCount,
            createdAt: Date()
        )
    }
    
    private static func selectBestClip(from clips: [Clip]) -> Clip? {
        // Filter out x and deprioritized
        let eligibleClips = clips.filter { clip in
            clip.reviewStatus != .x && clip.reviewStatus != .deprioritized
        }
        
        // Prefer circled takes
        if let circled = eligibleClips.first(where: { $0.reviewStatus == .circled }) {
            return circled
        }
        
        // Otherwise, select by highest AI score
        return eligibleClips.max { clip1, clip2 in
            let score1 = clip1.aiScores?.composite ?? 0
            let score2 = clip2.aiScores?.composite ?? 0
            return score1 < score2
        }
    }
}

struct Assembly: Identifiable {
    let id: UUID
    let projectId: String
    let mode: ProjectMode
    var items: [AssemblyItem]
    var totalDuration: Double
    var gapCount: Int
    var autoSelectedCount: Int
    var createdAt: Date
}

struct AssemblyItem: Identifiable {
    let id: UUID
    let clip: Clip
    let sceneName: String
    let setupName: String
    var isAutoSelected: Bool   // amber: no circle, used best score
    var isGap: Bool            // red: no takes at all
    var sortOrder: Int
}
