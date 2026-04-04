import Foundation
import XCTest
import SLATESharedTypes
@testable import IngestDaemon

final class IngestDaemonTests: XCTestCase {
    func testGRDBStorePersistsSyncAndAIScoreUpdates() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-ingest-\(UUID().uuidString).db")
        let store = try GRDBStore(path: databaseURL.path)

        let clip = Clip(
            projectId: UUID().uuidString,
            checksum: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            sourcePath: "/tmp/source.mov",
            sourceSize: 1_024,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 10,
            proxyPath: nil,
            proxyStatus: .pending,
            proxyChecksum: nil,
            narrativeMeta: .init(sceneNumber: "1", shotCode: "A", takeNumber: 1, cameraId: "A"),
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

        try await store.saveClip(clip)

        let audioTracks = [
            AudioTrack(trackIndex: 0, role: .boom, channelLabel: "boom", sampleRate: 48_000, bitDepth: 24)
        ]
        let syncResult = SyncResult(confidence: .high, method: .timecode, offsetFrames: 0)
        try await store.updateAudioSync(
            clipId: clip.id,
            audioTracks: audioTracks,
            syncResult: syncResult,
            syncedAudioPath: "/tmp/boom.wav"
        )

        let aiScores = AIScores(
            composite: 82,
            focus: 80,
            exposure: 81,
            stability: 84,
            audio: 83,
            performance: nil,
            contentDensity: nil,
            scoredAt: ISO8601DateFormatter().string(from: Date()),
            modelVersion: "test",
            reasoning: [
                ScoreReason(dimension: "focus", score: 80, flag: .info, message: "fixture")
            ]
        )
        try await store.updateAIScores(clipId: clip.id, aiScores: aiScores, status: .ready)

        let persisted = try await store.getClip(byId: clip.id)
        XCTAssertEqual(persisted?.audioTracks, audioTracks)
        XCTAssertEqual(persisted?.syncResult, syncResult)
        XCTAssertEqual(persisted?.syncedAudioPath, "/tmp/boom.wav")
        XCTAssertEqual(persisted?.aiScores, aiScores)
        XCTAssertEqual(persisted?.aiProcessingStatus, .ready)
    }
}
