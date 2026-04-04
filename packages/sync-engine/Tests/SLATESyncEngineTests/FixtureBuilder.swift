import AppKit
import AVFoundation
import CoreVideo
import Foundation
@testable import SLATESyncEngine

enum FixtureBuilder {
    private struct SendableAssetWriter: @unchecked Sendable {
        let writer: AVAssetWriter
    }

    struct FixturePair {
        let videoURL: URL
        let audioURL: URL
        let extraAudioURLs: [URL]
    }

    static func makeFixture(
        in directory: URL,
        name: String,
        offsetFrames: Int,
        fps: Double,
        durationSeconds: Double = 8,
        sampleRate: Double = 8_000,
        noiseLevel: Float = 0.02,
        clapTimes: [Double] = [1.0],
        useTimecode: Bool = false,
        timecodeStrings: (video: String, audio: String)? = nil,
        addDrift: Bool = false,
        makeThreeTrackSet: Bool = false
    ) throws -> FixturePair {
        let frameShiftSeconds = Double(offsetFrames) / fps
        let sampleCount = Int(durationSeconds * sampleRate)

        var camera = baseSignal(sampleCount: sampleCount, sampleRate: sampleRate, noiseLevel: noiseLevel)
        addClaps(into: &camera, sampleRate: sampleRate, times: clapTimes, amplitudes: clapTimes.enumerated().map { $0.offset == 0 ? 0.8 : 1.0 })

        var external = delay(signal: camera, bySeconds: frameShiftSeconds, sampleRate: sampleRate)
        if addDrift {
            external = timeStretch(signal: external, factor: 1.0002)
            external = Array(external.prefix(sampleCount))
            if external.count < sampleCount {
                external.append(contentsOf: Array(repeating: Float.zero, count: sampleCount - external.count))
            }
        }

        let videoURL = directory.appendingPathComponent("\(name)_video.wav")
        let audioURL = directory.appendingPathComponent("\(name)_audio.wav")
        try writeWAV(samples: camera, sampleRate: sampleRate, to: videoURL)
        try writeWAV(samples: external, sampleRate: sampleRate, to: audioURL)

        if let timecodeStrings {
            try writeTimecode(timecode: timecodeStrings.video, for: videoURL)
            try writeTimecode(timecode: timecodeStrings.audio, for: audioURL)
        } else if useTimecode {
            try writeTimecode(startFrames: 0, fps: fps, for: videoURL)
            try writeTimecode(startFrames: Double(offsetFrames), fps: fps, for: audioURL)
        }

        var extraAudioURLs: [URL] = []
        if makeThreeTrackSet {
            let boom = directory.appendingPathComponent("\(name)_boom.wav")
            let lav1 = directory.appendingPathComponent("\(name)_lav1.wav")
            let lav2 = directory.appendingPathComponent("\(name)_lav2.wav")

            try writeWAV(samples: scale(camera, by: 1.0), sampleRate: sampleRate, to: boom)
            try writeWAV(samples: lowPassed(scale(external, by: 0.8)), sampleRate: sampleRate, to: lav1)
            try writeWAV(samples: lowPassed(scale(external, by: 0.6)), sampleRate: sampleRate, to: lav2)
            extraAudioURLs = [boom, lav1, lav2]
        }

        return FixturePair(videoURL: videoURL, audioURL: audioURL, extraAudioURLs: extraAudioURLs)
    }

    static func makeDigitalSlateFixture(
        in directory: URL,
        name: String,
        videoStartTimecode: String,
        audioStartTimecode: String,
        fps: Double,
        durationSeconds: Double = 2,
        sampleRate: Double = 8_000
    ) async throws -> FixturePair {
        let sampleCount = Int(durationSeconds * sampleRate)
        let external = baseSignal(sampleCount: sampleCount, sampleRate: sampleRate, noiseLevel: 0.01)

        let videoURL = directory.appendingPathComponent("\(name)_video.mov")
        let audioURL = directory.appendingPathComponent("\(name)_audio.wav")
        try writeWAV(samples: external, sampleRate: sampleRate, to: audioURL)
        try writeTimecode(timecode: audioStartTimecode, for: audioURL)
        try await writeSlateVideo(startTimecode: videoStartTimecode, fps: fps, durationSeconds: durationSeconds, to: videoURL)

        return FixturePair(videoURL: videoURL, audioURL: audioURL, extraAudioURLs: [])
    }

    static func makeUncorrelatedFixture(
        in directory: URL,
        name: String,
        fps: Double,
        durationSeconds: Double = 8,
        sampleRate: Double = 8_000
    ) throws -> FixturePair {
        let sampleCount = Int(durationSeconds * sampleRate)
        let camera = baseSignal(sampleCount: sampleCount, sampleRate: sampleRate, noiseLevel: 0.01, seed: 42)
        let external = (0..<sampleCount).map { index -> Float in
            let time = Double(index) / sampleRate
            let bed = Float(
                sin(2 * Double.pi * 610 * time) * 0.32 +
                sin(2 * Double.pi * 1_130 * time) * 0.18
            )
            let pulse = index % 379 == 0 ? Float(0.55) : Float.zero
            return bed + pulse
        }

        let videoURL = directory.appendingPathComponent("\(name)_video.wav")
        let audioURL = directory.appendingPathComponent("\(name)_audio.wav")
        try writeWAV(samples: camera, sampleRate: sampleRate, to: videoURL)
        try writeWAV(samples: external, sampleRate: sampleRate, to: audioURL)

        return FixturePair(videoURL: videoURL, audioURL: audioURL, extraAudioURLs: [])
    }

    private static func baseSignal(sampleCount: Int, sampleRate: Double, noiseLevel: Float, seed: UInt64 = 42) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        return (0..<sampleCount).map { index in
            let time = Double(index) / sampleRate
            let speech = Float(sin(2 * Double.pi * 180 * time) * 0.16 + sin(2 * Double.pi * 320 * time) * 0.09)
            let ambience = Float.random(in: -noiseLevel...noiseLevel, using: &generator)
            return speech + ambience
        }
    }

    private static func addClaps(into signal: inout [Float], sampleRate: Double, times: [Double], amplitudes: [Float]) {
        let clapLength = Int(sampleRate * 0.01)
        for (index, time) in times.enumerated() {
            let start = Int(time * sampleRate)
            guard start + clapLength < signal.count else { continue }
            let amplitude = amplitudes[min(index, amplitudes.count - 1)]
            for frame in 0..<clapLength {
                let t = Double(frame) / sampleRate
                signal[start + frame] += amplitude * Float(sin(2 * Double.pi * 1_000 * t))
            }
        }
    }

    private static func delay(signal: [Float], bySeconds seconds: Double, sampleRate: Double) -> [Float] {
        let sampleOffset = Int((seconds * sampleRate).rounded())
        if sampleOffset == 0 { return signal }

        var result = Array(repeating: Float.zero, count: signal.count)
        for index in 0..<signal.count {
            let shiftedIndex = index - sampleOffset
            if signal.indices.contains(shiftedIndex) {
                result[index] = signal[shiftedIndex]
            }
        }
        return result
    }

    private static func timeStretch(signal: [Float], factor: Double) -> [Float] {
        guard !signal.isEmpty else { return [] }
        let targetCount = Int(Double(signal.count) * factor)
        return (0..<targetCount).map { index in
            let sourcePosition = Double(index) / factor
            let lower = Int(sourcePosition.rounded(.down))
            let upper = min(signal.count - 1, lower + 1)
            let fraction = Float(sourcePosition - Double(lower))
            return signal[lower] * (1 - fraction) + signal[upper] * fraction
        }
    }

    private static func scale(_ signal: [Float], by factor: Float) -> [Float] {
        signal.map { $0 * factor }
    }

    private static func lowPassed(_ signal: [Float]) -> [Float] {
        guard signal.count > 4 else { return signal }
        var filtered = signal
        for index in 2..<(signal.count - 2) {
            filtered[index] = (signal[index - 2] + signal[index - 1] + signal[index] + signal[index + 1] + signal[index + 2]) / 5
        }
        return filtered
    }

    private static func writeWAV(samples: [Float], sampleRate: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channel = buffer.floatChannelData![0]
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private static func writeTimecode(startFrames: Double, fps: Double, for url: URL) throws {
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("timecode.json")
        let payload = ["startFrames": startFrames, "fps": fps] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sidecarURL)
    }

    private static func writeTimecode(timecode: String, for url: URL) throws {
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("timecode.json")
        let payload = ["timecode": timecode] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: sidecarURL)
    }

    private static func writeSlateVideo(
        startTimecode: String,
        fps: Double,
        durationSeconds: Double,
        to url: URL
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let width = 1280
        let height = 720
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        precondition(writer.canAdd(videoInput))
        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let roundedFPS = max(Int(fps.rounded()), 1)
        let frameCount = max(1, Int(durationSeconds * Double(roundedFPS)))

        for frame in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }

            let timecode = addFrames(to: startTimecode, frameCount: frame, fps: fps)
            let image = makeSlateFrame(timecode: timecode, width: width, height: height)
            let pixelBuffer = try makePixelBuffer(from: image, width: width, height: height)
            let presentationTime = CMTime(value: Int64(frame), timescale: Int32(roundedFPS))
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        }

        videoInput.markAsFinished()
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

    private static func addFrames(to timecode: String, frameCount: Int, fps: Double) -> String {
        let parts = timecode.split(separator: ":").map(String.init)
        guard parts.count == 4,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              let seconds = Int(parts[2]),
              let frames = Int(parts[3]) else {
            return timecode
        }

        let nominalFPS = max(Int(fps.rounded()), 1)
        let totalFrames = (((hours * 60 + minutes) * 60 + seconds) * nominalFPS) + frames + frameCount
        let frameValue = totalFrames % nominalFPS
        let totalSeconds = totalFrames / nominalFPS
        let secondValue = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minuteValue = totalMinutes % 60
        let hourValue = (totalMinutes / 60) % 24
        return String(format: "%02d:%02d:%02d:%02d", hourValue, minuteValue, secondValue, frameValue)
    }

    private static func makeSlateFrame(timecode: String, width: Int, height: Int) -> CGImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let graphicsContext = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = graphicsContext

        NSColor.black.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()

        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let timecodeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 140, weight: .bold),
            .foregroundColor: NSColor.white
        ]

        let header = NSAttributedString(string: "DIGITAL SLATE", attributes: headerAttributes)
        let timecodeText = NSAttributedString(string: timecode, attributes: timecodeAttributes)
        header.draw(at: NSPoint(x: 80, y: height - 120))
        timecodeText.draw(at: NSPoint(x: 110, y: height / 2 - 60))

        return rep.cgImage!
    }

    private static func makePixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
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
            throw NSError(domain: "SLATESyncEngineTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to create pixel buffer"])
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NSError(domain: "SLATESyncEngineTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing pixel buffer base address"])
        }

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw NSError(domain: "SLATESyncEngineTests", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create CGContext"])
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}
