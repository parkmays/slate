import Foundation
import XCTest
@testable import IngestDaemon
import SLATESharedTypes

final class SoundReportParserTests: XCTestCase {
    func testParsesMinimalCSV() async throws {
        let csv = """
        Scene,Take,File Name
        12A,3,SOUND_001.WAV
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sound-test-\(UUID().uuidString).csv")
        try csv.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parser = SoundReportParser()
        let entries = try await parser.parse(fileURL: tmp)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].scene, "12A")
        XCTAssertEqual(entries[0].takeNumber, 3)
        XCTAssertEqual(entries[0].audioFilename, "SOUND_001.WAV")
    }

    func testMatchesBySyncedAudioFilename() {
        let entry = SoundReportEntry(
            scene: "1",
            shotCode: nil,
            takeNumber: 1,
            audioFilename: "boom.wav",
            circled: false,
            notes: nil,
            timecode: nil,
            channels: []
        )
        var clip = Clip(
            projectId: "p",
            checksum: "c",
            sourcePath: "/tmp/video.mov",
            sourceSize: 1,
            sourceFormat: .h264,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 1,
            narrativeMeta: NarrativeMeta(sceneNumber: "99", shotCode: "X", takeNumber: 9, cameraId: "A"),
            projectMode: .narrative
        )
        clip.syncedAudioPath = "/Volumes/sound/boom.wav"

        let parser = SoundReportParser()
        let results = parser.match(entries: [entry], against: [clip])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].confidence, 1.0)
        XCTAssertEqual(results[0].matchedClipId, clip.id)
    }

    func testMatchesSceneShotTake() {
        let entry = SoundReportEntry(
            scene: "12A",
            shotCode: "B",
            takeNumber: 2,
            audioFilename: "x.wav",
            circled: false,
            notes: nil,
            timecode: nil,
            channels: []
        )
        let clip = Clip(
            projectId: "p",
            checksum: "c",
            sourcePath: "/tmp/video.mov",
            sourceSize: 1,
            sourceFormat: .h264,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 1,
            narrativeMeta: NarrativeMeta(sceneNumber: "12a", shotCode: "b", takeNumber: 2, cameraId: "A"),
            projectMode: .narrative
        )

        let parser = SoundReportParser()
        let results = parser.match(entries: [entry], against: [clip])
        XCTAssertEqual(results[0].confidence, 0.90)
        XCTAssertEqual(results[0].matchedClipId, clip.id)
    }

    func testMergeChannelLabelsUpdatesTrackNames() {
        let existing = [
            AudioTrack(trackIndex: 0, role: .boom, channelLabel: "old", sampleRate: 48_000, bitDepth: 24)
        ]
        let merged = SoundReportParser.mergeChannelLabels(existing: existing, channels: ["Boom", "Lav 1"])
        XCTAssertEqual(merged[0].channelLabel, "Boom")
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[1].channelLabel, "Lav 1")
    }
}
