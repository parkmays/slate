import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SLATESharedTypes
import SLATESyncEngine
import XCTest
@testable import SLATEAIPipeline

final class SLATEAIPipelineTests: XCTestCase {
    private struct SendableAssetWriter: @unchecked Sendable {
        let writer: AVAssetWriter
    }

    func testPerformanceScorerBlendsGemmaInsightIntoNarrativeScore() async throws {
        let transcript = makeNarrativeTranscript()
        let scorer = PerformanceScorer { request in
            XCTAssertEqual(request.transcriptLanguage, "en-US")
            XCTAssertEqual(request.wordCount, transcript.words.count)
            return GemmaPerformanceInsightResponse(
                modelVersion: "google/gemma-4-E2B-it",
                score: 88,
                reasons: [
                    .init(
                        dimension: "performance",
                        score: 86,
                        flag: "info",
                        message: "Delivery feels controlled and intentional, with strong momentum through the middle of the take.",
                        timecode: nil
                    )
                ]
            )
        }

        let result = try await scorer.scorePerformance(
            transcript: transcript,
            scriptText: "The scene should build steadily without long hesitations.",
            clipMode: .narrative
        )

        XCTAssertEqual(result.modelVersion, "performance-hybrid-v2+google/gemma-4-E2B-it")
        XCTAssertGreaterThan(result.score ?? 0, 55)
        XCTAssertTrue(result.reasons.contains(where: { $0.message.contains("controlled and intentional") }))
    }

    func testPerformanceScorerFallsBackWhenGemmaInsightErrors() async throws {
        let scorer = PerformanceScorer { _ in
            throw NSError(
                domain: "SLATEAIPipelineTests",
                code: 17,
                userInfo: [NSLocalizedDescriptionKey: "Gemma helper is offline"]
            )
        }

        let result = try await scorer.scorePerformance(
            transcript: makeNarrativeTranscript(),
            scriptText: "",
            clipMode: .narrative
        )

        XCTAssertEqual(result.modelVersion, "performance-heuristic-v1")
        XCTAssertTrue(
            result.reasons.contains(where: {
                $0.flag == .warning && $0.message.contains("Gemma performance insight was unavailable")
            })
        )
    }

    func testAudioScorerFlagsClipping() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let audioURL = directory.appendingPathComponent("clipped.wav")
        try writeWAV(samples: makeClippedSignal(), sampleRate: 8_000, to: audioURL)

        let result = try await AudioScorer().scoreAudio(syncedAudioURL: audioURL)
        XCTAssertLessThan(result.audio, 90)
        XCTAssertTrue(result.reasons.contains(where: { $0.flag == .error }))
    }

    func testVisionScorerScoresSoftProxyBelowFocusThreshold() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let proxyURL = directory.appendingPathComponent("soft-proxy.mp4")
        try await writeProxyVideo(to: proxyURL, fps: 6, frameCount: 12) { frame in
            makeSoftFrame(width: 320, height: 180, frameIndex: frame)
        }

        let result = try await VisionScorer(sampleFPS: 3).scoreClip(proxyURL: proxyURL, fps: 24)
        XCTAssertLessThan(result.focus, 40)
    }

    func testCleanPipelineFixtureScoresAboveSeventyFive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let proxyURL = directory.appendingPathComponent("clean-proxy.mp4")
        let audioURL = directory.appendingPathComponent("clean-audio.wav")
        try await writeProxyVideo(to: proxyURL, fps: 6, frameCount: 12) { frame in
            makeSharpFrame(width: 320, height: 180, frameIndex: frame)
        }
        try writeWAV(samples: makeCleanDialogueSignal(sampleRate: 8_000, durationSeconds: 3), sampleRate: 8_000, to: audioURL)

        let pipeline = AIPipeline()
        let clip = Clip(
            id: UUID().uuidString,
            projectId: UUID().uuidString,
            checksum: "clean",
            sourcePath: proxyURL.path,
            sourceSize: 1,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 3,
            proxyPath: proxyURL.path,
            proxyStatus: .ready,
            proxyChecksum: nil,
            narrativeMeta: nil,
            documentaryMeta: nil,
            audioTracks: [],
            syncResult: .init(confidence: .high, method: .timecode, offsetFrames: 0, driftPPM: 0, clapDetectedAt: nil, verifiedAt: nil),
            syncedAudioPath: audioURL.path,
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

        let scores = try await pipeline.scoreClip(clip)
        XCTAssertGreaterThan(scores.composite, 75)
    }

    func testPipelineReturnsReasonsWhenMediaIsMissing() async throws {
        let pipeline = AIPipeline()
        let clip = Clip(
            id: UUID().uuidString,
            projectId: UUID().uuidString,
            checksum: "abc",
            sourcePath: "/tmp/source.mov",
            sourceSize: 1,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 5,
            proxyPath: nil,
            proxyStatus: .pending,
            proxyChecksum: nil,
            narrativeMeta: nil,
            documentaryMeta: nil,
            audioTracks: [],
            syncResult: .init(confidence: .medium, method: .waveformCorrelation, offsetFrames: 0, driftPPM: 0, clapDetectedAt: nil, verifiedAt: nil),
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

        let scores = try await pipeline.scoreClip(clip)
        XCTAssertEqual(scores.composite, 0)
        XCTAssertGreaterThanOrEqual(scores.reasoning.count, 2)
    }

    func testNarrativeClipIncludesPerformanceReasoning() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let proxyURL = directory.appendingPathComponent("narrative-proxy.mp4")
        let audioURL = directory.appendingPathComponent("narrative-audio.wav")
        try await writeProxyVideo(to: proxyURL, fps: 6, frameCount: 12) { frame in
            makeSharpFrame(width: 320, height: 180, frameIndex: frame)
        }
        try writeWAV(samples: makeCleanDialogueSignal(sampleRate: 8_000, durationSeconds: 3), sampleRate: 8_000, to: audioURL)

        let clip = makeClip(
            sourceURL: proxyURL,
            proxyURL: proxyURL,
            syncedAudioURL: audioURL,
            projectMode: .narrative
        )

        let scores = try await AIPipeline().scoreClip(clip)
        XCTAssertNotNil(scores.performance)
        XCTAssertGreaterThan(scores.performance ?? 0, 40)
        XCTAssertTrue(scores.reasoning.contains(where: { $0.dimension == "performance" }))
        XCTAssertTrue(scores.modelVersion.contains("performance-heuristic-v1"))
    }

    func testDocumentaryClipWithoutTranscriptKeepsContentDensityNilWithReason() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let proxyURL = directory.appendingPathComponent("documentary-proxy.mp4")
        let audioURL = directory.appendingPathComponent("documentary-audio.wav")
        try await writeProxyVideo(to: proxyURL, fps: 6, frameCount: 12) { frame in
            makeSharpFrame(width: 320, height: 180, frameIndex: frame)
        }
        try writeWAV(samples: makeCleanDialogueSignal(sampleRate: 8_000, durationSeconds: 3), sampleRate: 8_000, to: audioURL)

        let clip = makeClip(
            sourceURL: proxyURL,
            proxyURL: proxyURL,
            syncedAudioURL: audioURL,
            projectMode: .documentary
        )

        let scores = try await AIPipeline().scoreClip(clip)
        XCTAssertNotNil(scores.contentDensity)
        XCTAssertGreaterThan(scores.contentDensity ?? 0, 20)
        XCTAssertTrue(scores.reasoning.contains(where: { $0.dimension == "contentDensity" }))
    }

    func testTranscriptionFallbackProducesTimedTokensForDialogueLikeAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let audioURL = directory.appendingPathComponent("dialogue-like.wav")
        try writeWAV(
            samples: makeSegmentedDialogueSignal(sampleRate: 8_000, durationSeconds: 4),
            sampleRate: 8_000,
            to: audioURL
        )

        let transcript = try await TranscriptionService().transcribe(audioURL: audioURL)
        XCTAssertFalse(transcript.words.isEmpty)
        XCTAssertFalse(transcript.text.isEmpty)
        XCTAssertTrue(transcript.words.allSatisfy { $0.end > $0.start })
    }

    func testPipelineFallsBackToSourceAudioWhenSyncedAudioIsMissing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceAudioURL = directory.appendingPathComponent("source-audio.wav")
        try writeWAV(
            samples: makeSegmentedDialogueSignal(sampleRate: 8_000, durationSeconds: 4),
            sampleRate: 8_000,
            to: sourceAudioURL
        )

        let clip = makeClip(
            sourceURL: sourceAudioURL,
            proxyURL: nil,
            syncedAudioURL: nil,
            projectMode: .narrative
        )

        let analysis = try await AIPipeline().analyzeClip(clip)
        XCTAssertNotNil(analysis.transcript)
        XCTAssertFalse(analysis.transcript?.words.isEmpty ?? true)
        XCTAssertGreaterThan(analysis.aiScores.audio, 0)
    }

    func testIngestSequenceProducesStableSyncAndAIScores() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let proxyURL = directory.appendingPathComponent("ingest-proxy.mp4")
        let cameraAudioURL = directory.appendingPathComponent("camera.wav")
        let boomURL = directory.appendingPathComponent("boom.wav")
        let lav1URL = directory.appendingPathComponent("lav1.wav")
        let lav2URL = directory.appendingPathComponent("lav2.wav")

        try await writeProxyVideo(to: proxyURL, fps: 6, frameCount: 12) { frame in
            makeSharpFrame(width: 320, height: 180, frameIndex: frame)
        }

        let cameraSignal = makeCleanDialogueSignal(sampleRate: 8_000, durationSeconds: 3)
        try writeWAV(samples: cameraSignal, sampleRate: 8_000, to: cameraAudioURL)
        try writeWAV(samples: cameraSignal, sampleRate: 8_000, to: boomURL)
        try writeWAV(samples: cameraSignal.map { $0 * 0.85 }, sampleRate: 8_000, to: lav1URL)
        try writeWAV(samples: cameraSignal.map { $0 * 0.7 }, sampleRate: 8_000, to: lav2URL)
        try writeTimecode("01:00:00:00", for: cameraAudioURL)
        try writeTimecode("01:00:00:00", for: boomURL)
        try writeTimecode("01:00:00:00", for: lav1URL)
        try writeTimecode("01:00:00:00", for: lav2URL)

        let syncEngine = SyncEngine()
        let syncResult = try await syncEngine.syncClip(videoURL: cameraAudioURL, audioFiles: [boomURL], fps: 24)
        let audioTracks = await syncEngine.assignAudioRoles(tracks: [boomURL, lav1URL, lav2URL])

        let clip = makeClip(
            sourceURL: cameraAudioURL,
            proxyURL: proxyURL,
            syncedAudioURL: boomURL,
            projectMode: .narrative,
            audioTracks: audioTracks,
            syncResult: syncResult
        )

        let scores = try await AIPipeline().scoreClip(clip)
        XCTAssertEqual(syncResult.method, .timecode)
        XCTAssertEqual(syncResult.offsetFrames, 0)
        XCTAssertEqual(audioTracks.count, 3)
        XCTAssertTrue(audioTracks.contains(where: { $0.role == .boom }))
        XCTAssertGreaterThan(scores.composite, 70)
        XCTAssertFalse(scores.reasoning.isEmpty)
    }

    private func makeClippedSignal() -> [Float] {
        (0..<8_000).map { index in
            if index % 500 == 0 { return 1.0 }
            return Float(sin(2 * Double.pi * 220 * Double(index) / 8_000) * 0.9)
        }
    }

    private func makeNarrativeTranscript() -> Transcript {
        Transcript(
            text: "I can hold the moment. Let the scene breathe before the turn.",
            language: "en-US",
            words: [
                .init(start: 0.00, end: 0.26, text: "I"),
                .init(start: 0.28, end: 0.56, text: "can"),
                .init(start: 0.58, end: 0.93, text: "hold"),
                .init(start: 0.96, end: 1.31, text: "the"),
                .init(start: 1.33, end: 1.78, text: "moment."),
                .init(start: 2.18, end: 2.55, text: "Let"),
                .init(start: 2.58, end: 2.91, text: "the"),
                .init(start: 2.94, end: 3.36, text: "scene"),
                .init(start: 3.39, end: 3.84, text: "breathe"),
                .init(start: 4.28, end: 4.67, text: "before"),
                .init(start: 4.70, end: 5.02, text: "the"),
                .init(start: 5.05, end: 5.48, text: "turn.")
            ]
        )
    }

    private func makeCleanDialogueSignal(sampleRate: Double, durationSeconds: Double) -> [Float] {
        let sampleCount = Int(sampleRate * durationSeconds)
        return (0..<sampleCount).map { index in
            let time = Double(index) / sampleRate
            let envelope: Double
            switch time {
            case ..<0.6, 2.4...:
                envelope = 0.002
            default:
                envelope = 0.22
            }

            let speech = sin(2 * Double.pi * 180 * time) * 0.8 + sin(2 * Double.pi * 320 * time) * 0.2
            return Float(speech * envelope)
        }
    }

    private func makeSegmentedDialogueSignal(sampleRate: Double, durationSeconds: Double) -> [Float] {
        let sampleCount = Int(sampleRate * durationSeconds)
        return (0..<sampleCount).map { index in
            let time = Double(index) / sampleRate
            let envelope: Double
            switch time {
            case 0.4..<1.1:
                envelope = 0.18
            case 1.5..<2.2:
                envelope = 0.22
            case 2.6..<3.3:
                envelope = 0.16
            default:
                envelope = 0.0015
            }

            let voiced = sin(2 * Double.pi * 190 * time) * 0.75 + sin(2 * Double.pi * 310 * time) * 0.25
            return Float(voiced * envelope)
        }
    }

    private func writeWAV(samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            buffer.floatChannelData![0][index] = sample
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func writeTimecode(_ timecode: String, for url: URL) throws {
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("timecode.json")
        let payload = ["timecode": timecode]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sidecarURL)
    }

    private func makeClip(
        sourceURL: URL,
        proxyURL: URL?,
        syncedAudioURL: URL?,
        projectMode: ProjectMode,
        audioTracks: [AudioTrack] = [],
        syncResult: SyncResult = .init(confidence: .high, method: .timecode, offsetFrames: 0)
    ) -> Clip {
        Clip(
            id: UUID().uuidString,
            projectId: UUID().uuidString,
            checksum: "fixture",
            sourcePath: sourceURL.path,
            sourceSize: 1,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 3,
            proxyPath: proxyURL?.path,
            proxyStatus: proxyURL == nil ? .pending : .ready,
            proxyChecksum: nil,
            narrativeMeta: projectMode == .narrative ? .init(sceneNumber: "1", shotCode: "A", takeNumber: 1, cameraId: "A") : nil,
            documentaryMeta: projectMode == .documentary ? .init(subjectName: "Subject", subjectId: UUID().uuidString, shootingDay: 1, sessionLabel: "Interview") : nil,
            audioTracks: audioTracks,
            syncResult: syncResult,
            syncedAudioPath: syncedAudioURL?.path,
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
            projectMode: projectMode
        )
    }

    private func writeProxyVideo(
        to url: URL,
        fps: Int32,
        frameCount: Int,
        frameProvider: (Int) -> CGImage
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = 320
        let height = 180
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        precondition(writer.canAdd(input))
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let image = frameProvider(frame)
            let pixelBuffer = try makePixelBuffer(from: image, width: width, height: height)
            let time = CMTime(value: Int64(frame), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }

        input.markAsFinished()
        try await finishWriting(writer)
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        let sendableWriter = SendableAssetWriter(writer: writer)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = sendableWriter.writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makePixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(domain: "SLATEAIPipelineTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to create pixel buffer"])
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "SLATEAIPipelineTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing pixel buffer base address"])
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw NSError(domain: "SLATEAIPipelineTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create CGContext"])
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private func makeSharpFrame(width: Int, height: Int, frameIndex: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(CGColor(red: 0.50, green: 0.50, blue: 0.50, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let squareSize = 8
        for row in stride(from: 0, to: height, by: squareSize) {
            for column in stride(from: 0, to: width, by: squareSize) {
                let isDark = ((row / squareSize) + (column / squareSize) + frameIndex) % 2 == 0
                let tone: CGFloat = isDark ? 0.10 : 0.90
                context.setFillColor(CGColor(red: tone, green: tone, blue: tone, alpha: 1))
                context.fill(CGRect(x: column, y: row, width: squareSize, height: squareSize))
            }
        }

        context.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1))
        for column in stride(from: 0, to: width, by: 24) {
            context.fill(CGRect(x: column, y: 0, width: 2, height: height))
        }

        return context.makeImage()!
    }

    private func makeSoftFrame(width: Int, height: Int, frameIndex: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        let baseTone = 0.48 + (Double(frameIndex % 2) * 0.01)
        context.setFillColor(CGColor(red: baseTone, green: baseTone, blue: baseTone, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for row in stride(from: 0, to: height, by: 30) {
            let tone = 0.50 + (Double(row) / Double(height) * 0.03)
            context.setFillColor(CGColor(red: tone, green: tone, blue: tone, alpha: 1))
            context.fill(CGRect(x: 0, y: row, width: width, height: 30))
        }

        return context.makeImage()!
    }
}
