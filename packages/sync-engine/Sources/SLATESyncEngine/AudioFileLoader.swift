import AVFoundation
import CoreMedia
import Foundation

enum AudioFileLoader {
    static func loadMonoSamples(from url: URL, limitSeconds: Double? = nil) async throws -> LoadedAudio {
        if let direct = try? loadUsingAudioFile(from: url, limitSeconds: limitSeconds) {
            return direct
        }
        return try await loadUsingAssetReader(from: url, limitSeconds: limitSeconds)
    }

    private static func loadUsingAudioFile(from url: URL, limitSeconds: Double?) throws -> LoadedAudio {
        let file = try AVAudioFile(forReading: url)
        let processingFormat = file.processingFormat
        let totalFrames = Int(file.length)
        let framesToRead = limitSeconds.map { min(totalFrames, Int($0 * processingFormat.sampleRate)) } ?? totalFrames
        let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(framesToRead))!
        try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
        let samples = interleavedMono(from: buffer)
        return LoadedAudio(
            samples: samples,
            sampleRate: processingFormat.sampleRate,
            channels: Int(processingFormat.channelCount),
            duration: Double(samples.count) / processingFormat.sampleRate
        )
    }

    private static func loadUsingAssetReader(from url: URL, limitSeconds: Double?) async throws -> LoadedAudio {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw NSError(domain: "SLATESyncEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found in \(url.lastPathComponent)"])
        }

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else {
            throw NSError(
                domain: "SLATESyncEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: reader.error?.localizedDescription ?? "Failed to start AVAssetReader"]
            )
        }

        var sampleRate = 48_000.0
        var channels = 1
        if let formatDescription = try await track.load(.formatDescriptions).first {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
                sampleRate = asbd.mSampleRate
                channels = Int(asbd.mChannelsPerFrame)
            }
        }

        let maxSamples = limitSeconds.map { Int($0 * sampleRate) }
        var monoSamples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { bytes in
                guard let destination = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: destination)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
            data.withUnsafeBytes { bytes in
                let floatSamples = bytes.bindMemory(to: Float.self)
                monoSamples.reserveCapacity(monoSamples.count + frameCount)
                for frame in 0..<frameCount {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += floatSamples[frame * channels + channel]
                    }
                    monoSamples.append(sum / Float(channels))
                }
            }

            if let maxSamples, monoSamples.count >= maxSamples {
                monoSamples = Array(monoSamples.prefix(maxSamples))
                break
            }
        }

        return LoadedAudio(
            samples: monoSamples,
            sampleRate: sampleRate,
            channels: channels,
            duration: Double(monoSamples.count) / sampleRate
        )
    }

    private static func interleavedMono(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameLength = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard channels > 0 else { return [] }

        if let floatData = buffer.floatChannelData {
            if channels == 1 {
                return Array(UnsafeBufferPointer(start: floatData[0], count: frameLength))
            }

            var result = Array(repeating: Float.zero, count: frameLength)
            for channel in 0..<channels {
                let source = UnsafeBufferPointer(start: floatData[channel], count: frameLength)
                for index in 0..<frameLength {
                    result[index] += source[index] / Float(channels)
                }
            }
            return result
        }

        return []
    }
}
