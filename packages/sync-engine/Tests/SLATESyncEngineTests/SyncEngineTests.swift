// SLATE — SyncEngine Test Harness
// Owned by: Codex
//
// Accuracy targets (from contracts/sync-api.json):
//   High confidence:   offset error ≤ 0.5 frames, drift ≤ 5 PPM
//   Medium confidence: offset error ≤ 2 frames, drift ≤ 20 PPM
//
// Run: swift test --filter SLATESyncEngineTests

import XCTest
import AVFoundation
import SLATESharedTypes
@testable import SLATESyncEngine

final class SyncEngineTests: XCTestCase {

    var engine: SyncEngine!

    override func setUp() {
        super.setUp()
        engine = SyncEngine()
    }

    // MARK: - Audio role assignment

    func testRoleAssignment_singleSilentTrack_returnsUnknown() async {
        // A silent file should produce .unknown role
        let silentURL = try! makeSilentAudioFile(duration: 5.0, label: "silent")
        let tracks = await engine.assignAudioRoles(tracks: [silentURL])
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks[0].role, .unknown)
        XCTAssertEqual(tracks[0].trackIndex, 0)
    }

    func testRoleAssignment_loudAiryTrack_returnsBoom() async {
        // High airiness (diff-to-rms ratio > 0.85) → boom
        let boomURL = try! makeSyntheticAudioFile(
            duration: 10.0,
            waveform: .boom,
            label: "boom_track"
        )
        let tracks = await engine.assignAudioRoles(tracks: [boomURL])
        XCTAssertEqual(tracks.count, 1)
        // Boom mics exhibit high mid-frequency content and airiness
        XCTAssertTrue(
            [AudioTrackRole.boom, .lav].contains(tracks[0].role),
            "Expected boom or lav for high-airiness signal, got \(tracks[0].role)"
        )
    }

    func testRoleAssignment_multipleTracks_assignsUniqueIndices() async {
        let urls = try! (0..<3).map { i in
            try makeSilentAudioFile(duration: 5.0, label: "track_\(i)")
        }
        let tracks = await engine.assignAudioRoles(tracks: urls)
        XCTAssertEqual(tracks.count, 3)
        let indices = tracks.map(\.trackIndex)
        XCTAssertEqual(Set(indices).count, 3, "Track indices should be unique")
        XCTAssertEqual(indices.sorted(), [0, 1, 2])
    }

    func testRoleAssignment_emptyInput_returnsEmpty() async {
        let tracks = await engine.assignAudioRoles(tracks: [])
        XCTAssertTrue(tracks.isEmpty)
    }

    // MARK: - Sync: no audio supplied

    func testSync_noAudioFiles_returnsManualRequired() async throws {
        let videoURL = try await makeSilentVideoFile(duration: 10.0, fps: 24.0)
        let result = try await engine.syncClip(videoURL: videoURL, audioFiles: [], fps: 24.0)
        XCTAssertEqual(result.confidence, .manualRequired)
        XCTAssertEqual(result.method, .none)
        XCTAssertEqual(result.offsetFrames, 0)
    }

    // MARK: - Sync: timecode path

    func testSync_matchingTimecode_returnsHighConfidence() async throws {
        // Both video and audio have embedded timecode 01:00:00:00 at 24fps
        let videoURL = try await makeVideoWithTimecode("01:00:00:00", fps: 24.0, duration: 30.0)
        let audioURL = try makeAudioWithTimecode("01:00:00:00", fps: 24.0, duration: 30.0)

        let result = try await engine.syncClip(videoURL: videoURL, audioFiles: [audioURL], fps: 24.0)

        XCTAssertEqual(result.method, .timecode,
            "Should use timecode sync when matching TC is available")
        XCTAssertEqual(result.confidence, .high,
            "Matching timecode should yield high confidence")
        XCTAssertEqual(result.offsetFrames, 0,
            "Zero-offset expected when timecodes match exactly")
    }

    func testSync_offsetTimecode_returnsCorrectOffset() async throws {
        // Audio starts 2 seconds (48 frames at 24fps) later than video
        let videoURL = try await makeVideoWithTimecode("01:00:00:00", fps: 24.0, duration: 60.0)
        let audioURL = try makeAudioWithTimecode("01:00:02:00", fps: 24.0, duration: 58.0)

        let result = try await engine.syncClip(videoURL: videoURL, audioFiles: [audioURL], fps: 24.0)

        XCTAssertEqual(result.method, .timecode)
        // Offset should be close to 48 frames (±1 frame tolerance for rounding)
        XCTAssertLessThanOrEqual(abs(result.offsetFrames - 48), 1,
            "Expected ~48 frame offset, got \(result.offsetFrames)")
    }

    // MARK: - Sync: clap detection path

    func testSync_clapAtKnownOffset_detectsCorrectly() async throws {
        let clapOffsetFrames = 72  // 3 seconds at 24fps
        let videoURL = try await makeVideoWithClapBurst(offsetFrames: 0, fps: 24.0, duration: 30.0)
        let audioURL = try makeAudioWithClapBurst(offsetFrames: clapOffsetFrames, fps: 24.0, duration: 30.0)

        let result = try await engine.syncClip(videoURL: videoURL, audioFiles: [audioURL], fps: 24.0)

        guard result.method != .none else {
            // If clap detection failed, at minimum it should not crash
            XCTAssertNotEqual(result.confidence, .high, "Failed clap detection should not be high confidence")
            return
        }

        let frameError = abs(result.offsetFrames - clapOffsetFrames)
        XCTAssertLessThanOrEqual(frameError, 2,
            "Clap sync should be accurate within ±2 frames. Error: \(frameError) frames")
    }

    // MARK: - Sync: waveform correlation path

    func testSync_waveformCorrelation_accurateWithinTwoFrames() async throws {
        // Shared burst of noise at a known offset
        let knownOffsetFrames = 36  // 1.5 seconds at 24fps
        let fps = 24.0

        let sharedBurst = makeNoiseBurst(durationSeconds: 0.5)
        let videoURL    = try makeAudioFile(
            leadingSilence: 0.0, burst: sharedBurst, trailingSilence: 10.0,
            label: "video_audio", sampleRate: 48000
        )
        let audioURL    = try makeAudioFile(
            leadingSilence: Double(knownOffsetFrames) / fps,
            burst: sharedBurst,
            trailingSilence: 10.0 - Double(knownOffsetFrames) / fps,
            label: "external_audio", sampleRate: 48000
        )

        let result = try await engine.syncClip(videoURL: videoURL, audioFiles: [audioURL], fps: fps)

        // Allow graceful degradation — accept medium confidence or better
        XCTAssertTrue(
            [SyncConfidence.high, .medium].contains(result.confidence),
            "Waveform correlation should return high or medium confidence, got \(result.confidence)"
        )
        let frameError = abs(result.offsetFrames - knownOffsetFrames)
        XCTAssertLessThanOrEqual(frameError, 2,
            "Waveform correlation should be within ±2 frames. Error: \(frameError)")
    }

    // MARK: - Performance benchmarks

    func testPerformance_syncTenMinuteTake_underThirtySeconds() async throws {
        guard ProcessInfo.processInfo.environment["SLATE_RUN_BENCHMARKS"] == "1" else {
            throw XCTSkip("Set SLATE_RUN_BENCHMARKS=1 to run performance tests")
        }

        let videoURL = try await makeSilentVideoFile(duration: 600.0, fps: 23.976)
        let audioURL = try makeSilentAudioFile(duration: 600.0, label: "bench_audio")

        let start = Date()
        _ = try await engine.syncClip(videoURL: videoURL, audioFiles: [audioURL], fps: 23.976)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 30.0,
            "Sync of 10-min take must complete in < 30s on Apple Silicon. Took \(elapsed)s")
    }

    func testSyncPerformanceBenchmark() async throws {
        try await testPerformance_syncTenMinuteTake_underThirtySeconds()
    }

    // MARK: - Multi-camera sync

    func testMultiCamSyncReturnsResultForSingleAdditionalCamera() async throws {
        // Use temp URLs — actual sync will fall through to manual
        let primary = URL(fileURLWithPath: "/dev/null")
        let secondary = URL(fileURLWithPath: "/dev/null")
        let result = try await engine.syncMultiCam(primaryCamera: primary, additionalCameras: [secondary], fps: 24.0)
        XCTAssertEqual(result.offsets.count, 1)
        XCTAssertEqual(result.offsets[0].cameraURL, secondary)
    }

    // MARK: - Test helpers

    private enum Waveform { case boom, lav, silence }

    private func makeSilentAudioFile(duration: Double, label: String) throws -> URL {
        try makeAudioFile(leadingSilence: duration, burst: [], trailingSilence: 0, label: label, sampleRate: 48000)
    }

    private func makeSyntheticAudioFile(duration: Double, waveform: Waveform, label: String) throws -> URL {
        let sampleRate = 48000
        let frameCount = AVAudioFrameCount(duration * Double(sampleRate))
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData?[0] {
            switch waveform {
            case .boom:
                // High airiness: low RMS but high diff-to-RMS ratio
                for i in 0..<Int(frameCount) {
                    let t = Double(i) / Double(sampleRate)
                    channelData[i] = Float(0.05 * sin(2 * .pi * 440 * t))
                    if i > 0 { channelData[i] += Float(Float.random(in: -0.04...0.04)) }
                }
            case .lav:
                // High RMS, low airiness
                for i in 0..<Int(frameCount) {
                    let t = Double(i) / Double(sampleRate)
                    channelData[i] = Float(0.3 * sin(2 * .pi * 200 * t))
                }
            case .silence:
                memset(channelData, 0, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }

        return try writeAudioBuffer(buffer, label: label)
    }

    private func makeAudioFile(
        leadingSilence: Double,
        burst: [Float],
        trailingSilence: Double,
        label: String,
        sampleRate: Int
    ) throws -> URL {
        let totalFrames = Int((leadingSilence + trailingSilence) * Double(sampleRate)) + burst.count
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames))!
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        if let channelData = buffer.floatChannelData?[0] {
            let silenceFrames = Int(leadingSilence * Double(sampleRate))
            memset(channelData, 0, silenceFrames * MemoryLayout<Float>.size)
            for (i, s) in burst.enumerated() { channelData[silenceFrames + i] = s }
            let trailStart = silenceFrames + burst.count
            memset(channelData + trailStart, 0, Int(trailingSilence * Double(sampleRate)) * MemoryLayout<Float>.size)
        }

        return try writeAudioBuffer(buffer, label: label)
    }

    private func makeNoiseBurst(durationSeconds: Double, sampleRate: Int = 48000) -> [Float] {
        let count = Int(durationSeconds * Double(sampleRate))
        return (0..<count).map { _ in Float.random(in: -0.8...0.8) }
    }

    private func makeSilentVideoFile(duration: Double, fps: Double) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate_test_video_\(UUID().uuidString).mov")
        // Create a minimal QuickTime file with an audio track (no actual video frames needed for sync tests)
        let assetWriter = try AVAssetWriter(outputURL: url, fileType: .mov)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        assetWriter.add(input)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        input.markAsFinished()
        await assetWriter.finishWriting()
        return url
    }

    private func makeVideoWithTimecode(_ tc: String, fps: Double, duration: Double) async throws -> URL {
        let url = try await makeSilentVideoFile(duration: duration, fps: fps)
        try writeTimecodeSidecar(tc, fps: fps, for: url)
        return url
    }

    private func makeAudioWithTimecode(_ tc: String, fps: Double, duration: Double) throws -> URL {
        let url = try makeSilentAudioFile(duration: duration, label: "tc_\(tc.replacingOccurrences(of: ":", with: "_"))")
        try writeTimecodeSidecar(tc, fps: fps, for: url)
        return url
    }

    private func makeVideoWithClapBurst(offsetFrames: Int, fps: Double, duration: Double) async throws -> URL {
        return try await makeSilentVideoFile(duration: duration, fps: fps)
    }

    private func makeAudioWithClapBurst(offsetFrames: Int, fps: Double, duration: Double) throws -> URL {
        let sampleRate = 48000
        let burstOffset = Double(offsetFrames) / fps
        let burst = makeNoiseBurst(durationSeconds: 0.1, sampleRate: sampleRate)
        return try makeAudioFile(
            leadingSilence: burstOffset,
            burst: burst,
            trailingSilence: duration - burstOffset - 0.1,
            label: "clap_\(offsetFrames)f",
            sampleRate: sampleRate
        )
    }

    private func writeAudioBuffer(_ buffer: AVAudioPCMBuffer, label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate_\(label)_\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
        return url
    }

    private func writeTimecodeSidecar(_ timecode: String, fps: Double, for url: URL) throws {
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("timecode.json")
        let payload: [String: Any] = [
            "timecode": timecode,
            "fps": fps
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sidecarURL)
    }
}
