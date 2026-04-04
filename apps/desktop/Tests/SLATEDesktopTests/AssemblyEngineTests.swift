import Foundation
import Testing
@testable import SLATECore
@testable import SLATESharedTypes

@Suite("AssemblyEngine narrative mode")
struct NarrativeAssemblyEngineTests {
    @Test("Prefers circled takes, then highest AI score by setup")
    func narrativeOrdering() {
        let project = Project(id: "project-1", name: "Feature", mode: .narrative)
        let clips = [
            makeNarrativeClip(id: "10A-1", projectId: project.id, scene: "10", shot: "A", take: 1, score: 62, status: .unreviewed),
            makeNarrativeClip(id: "10A-2", projectId: project.id, scene: "10", shot: "A", take: 2, score: 88, status: .circled),
            makeNarrativeClip(id: "10B-1", projectId: project.id, scene: "10", shot: "B", take: 1, score: 91, status: .flagged),
            makeNarrativeClip(id: "11A-1", projectId: project.id, scene: "11", shot: "A", take: 1, score: 70, status: .unreviewed),
            makeNarrativeClip(id: "11A-2", projectId: project.id, scene: "11", shot: "A", take: 2, score: 84, status: .unreviewed)
        ]

        let assembly = AssemblyEngine().buildAssembly(project: project, clips: clips)

        #expect(assembly.clips.map(\.clipId) == ["10A-2", "10B-1", "11A-2"])
        #expect(assembly.clips.map(\.sceneLabel) == ["10A", "10B", "11A"])
        #expect(assembly.clips.allSatisfy { $0.role == .primary })
    }
}

@Suite("AssemblyEngine documentary mode")
struct DocumentaryAssemblyEngineTests {
    @Test("Applies subject filters, topic filters, and preferred order")
    func documentaryOrdering() {
        let project = Project(id: "project-2", name: "Doc", mode: .documentary)
        let interviewTrack = AudioTrack(trackIndex: 0, role: .boom, channelLabel: "Boom", sampleRate: 48_000, bitDepth: 24)
        let clips = [
            makeDocumentaryClip(id: "c1", projectId: project.id, subjectId: "s1", subjectName: "Ana", tags: ["history"], density: 60, status: .circled, audioTracks: [interviewTrack]),
            makeDocumentaryClip(id: "c2", projectId: project.id, subjectId: "s2", subjectName: "Ben", tags: ["history"], density: 80, status: .circled, audioTracks: [interviewTrack]),
            makeDocumentaryClip(id: "c3", projectId: project.id, subjectId: "s2", subjectName: "Ben", tags: ["history"], density: 72, status: .circled, audioTracks: []),
            makeDocumentaryClip(id: "c4", projectId: project.id, subjectId: "s1", subjectName: "Ana", tags: ["sports"], density: 99, status: .circled, audioTracks: [])
        ]

        let assembly = AssemblyEngine().buildAssembly(
            project: project,
            clips: clips,
            options: AssemblyGenerationOptions(
                selectedSubjectIds: ["s2", "s1"],
                selectedTopicTags: ["history"],
                preferredClipOrder: ["c3", "c2", "c1"]
            )
        )

        #expect(assembly.clips.map(\.clipId) == ["c3", "c2", "c1"])
        #expect(assembly.clips.first?.role == .broll)
        #expect(assembly.clips.dropFirst().allSatisfy { $0.role == .interview })
    }
}

@Suite("AssemblyStore")
struct AssemblyStoreTests {
    @MainActor
    @Test("Exports a version record and keeps recall history")
    func exportHistoryRoundTrip() async throws {
        let tempDB = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-assembly-\(UUID().uuidString).db")
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: tempDB)
            try? FileManager.default.removeItem(at: exportDirectory)
        }

        let store = AssemblyStore(dbPath: tempDB.path)
        let project = Project(id: "project-3", name: "Feature", mode: .narrative)
        let clips = [
            makeNarrativeClip(id: "20A-1", projectId: project.id, scene: "20", shot: "A", take: 1, score: 82, status: .circled)
        ]

        await store.load(project: project)
        try await store.generateAssembly(project: project, clips: clips, options: .init(name: "Scene 20 Selects"))
        let artifact = try await store.exportCurrentAssembly(
            clips: clips,
            outputDirectory: exportDirectory
        )

        #expect(FileManager.default.fileExists(atPath: artifact.filePath))
        #expect(store.versions.count == 1)
        #expect(store.versions.first?.assembly.name == "Scene 20 Selects")
        #expect(store.currentAssembly?.version == 1)
    }
}

private func makeNarrativeClip(
    id: String,
    projectId: String,
    scene: String,
    shot: String,
    take: Int,
    score: Double,
    status: ReviewStatus
) -> Clip {
    Clip(
        id: id,
        projectId: projectId,
        checksum: String(repeating: "a", count: 64),
        sourcePath: "/tmp/\(id).mov",
        sourceSize: 1_024,
        sourceFormat: .proRes422HQ,
        sourceFps: 24,
        sourceTimecodeStart: "01:00:00:00",
        duration: 8,
        proxyPath: "/tmp/\(id)_proxy.mp4",
        proxyStatus: .ready,
        narrativeMeta: .init(sceneNumber: scene, shotCode: shot, takeNumber: take, cameraId: "A"),
        aiScores: AIScores(
            composite: score,
            focus: score,
            exposure: score,
            stability: score,
            audio: score,
            scoredAt: ISO8601DateFormatter().string(from: Date()),
            modelVersion: "fixture"
        ),
        reviewStatus: status,
        projectMode: .narrative
    )
}

private func makeDocumentaryClip(
    id: String,
    projectId: String,
    subjectId: String,
    subjectName: String,
    tags: [String],
    density: Double,
    status: ReviewStatus,
    audioTracks: [AudioTrack]
) -> Clip {
    Clip(
        id: id,
        projectId: projectId,
        checksum: String(repeating: "b", count: 64),
        sourcePath: "/tmp/\(id).mov",
        sourceSize: 1_024,
        sourceFormat: .proRes422HQ,
        sourceFps: 23.976,
        sourceTimecodeStart: "01:00:00:00",
        duration: 12,
        proxyPath: "/tmp/\(id)_proxy.mp4",
        proxyStatus: .ready,
        documentaryMeta: .init(
            subjectName: subjectName,
            subjectId: subjectId,
            shootingDay: 1,
            sessionLabel: "Interview",
            topicTags: tags,
            interviewerOffscreen: audioTracks.isEmpty
        ),
        audioTracks: audioTracks,
        aiScores: AIScores(
            composite: density,
            focus: 70,
            exposure: 70,
            stability: 70,
            audio: 70,
            contentDensity: density,
            scoredAt: ISO8601DateFormatter().string(from: Date()),
            modelVersion: "fixture"
        ),
        reviewStatus: status,
        projectMode: .documentary
    )
}
