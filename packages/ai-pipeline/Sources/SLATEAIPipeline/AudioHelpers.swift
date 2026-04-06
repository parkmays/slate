import AVFoundation
import Accelerate
import CoreMedia
import Foundation

enum AudioHelpers {
    static func loadMonoSamples(from url: URL) async throws -> (samples: [Float], sampleRate: Double, channels: Int) {
        if let direct = try? loadUsingAudioFile(from: url) {
            return direct
        }
        return try await loadUsingAssetReader(from: url)
    }

    private static func loadUsingAudioFile(from url: URL) throws -> (samples: [Float], sampleRate: Double, channels: Int) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = Int(file.length)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        try file.read(into: buffer)

        return (
            samples: interleavedMono(from: buffer, channels: Int(format.channelCount), frameCount: frameCount),
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount)
        )
    }

    private static func loadUsingAssetReader(from url: URL) async throws -> (samples: [Float], sampleRate: Double, channels: Int) {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw NSError(domain: "AudioHelpers", code: 1, userInfo: [NSLocalizedDescriptionKey: "No audio track found in \(url.lastPathComponent)"])
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
        guard reader.canAdd(output) else {
            throw NSError(domain: "AudioHelpers", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to read embedded audio from \(url.lastPathComponent)"])
        }

        reader.add(output)
        reader.startReading()

        var sampleRate = 48_000.0
        var channels = 1
        let formatDescriptions = try await track.load(.formatDescriptions)
        if let formatDescription = formatDescriptions.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee {
            sampleRate = asbd.mSampleRate
            channels = Int(asbd.mChannelsPerFrame)
        }

        var monoSamples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }

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
        }

        return (samples: monoSamples, sampleRate: sampleRate, channels: channels)
    }

    private static func interleavedMono(from buffer: AVAudioPCMBuffer, channels: Int, frameCount: Int) -> [Float] {
        let samples: [Float]

        if let channelData = buffer.floatChannelData {
            if channels == 1 {
                samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            } else {
                var mono = Array(repeating: Float.zero, count: frameCount)
                for channel in 0..<channels {
                    let source = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
                    for index in 0..<frameCount {
                        mono[index] += source[index] / Float(channels)
                    }
                }
                samples = mono
            }
        } else {
            samples = []
        }

        return samples
    }

    static func timecodeString(for seconds: Double) -> String {
        let totalMilliseconds = Int((seconds * 1_000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let secs = (totalMilliseconds % 60_000) / 1_000
        let millis = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }

    static func downsample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > targetRate else { return samples }
        let stride = max(1, Int((sourceRate / targetRate).rounded(.down)))
        guard stride > 1 else { return samples }

        var result: [Float] = []
        result.reserveCapacity(samples.count / stride)
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + stride)
            let slice = samples[index..<end]
            let mean = slice.reduce(Float.zero, +) / Float(slice.count)
            result.append(mean)
            index += stride
        }
        return result
    }

    static func movingAverage(_ samples: [Float], windowSize: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let clampedWindow = max(1, windowSize)
        guard clampedWindow > 1 else { return samples }

        var result = Array(repeating: Float.zero, count: samples.count)
        var runningTotal: Float = 0

        for index in samples.indices {
            runningTotal += samples[index]
            if index >= clampedWindow {
                runningTotal -= samples[index - clampedWindow]
            }
            let divisor = min(index + 1, clampedWindow)
            result[index] = runningTotal / Float(divisor)
        }

        return result
    }

    static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let power = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return sqrt(power)
    }

    static func percentile(_ samples: [Float], percentile: Double) -> Float {
        guard !samples.isEmpty else { return 0 }
        let ordered = samples.sorted()
        let clamped = max(0, min(1, percentile))
        let index = Int((Double(ordered.count - 1) * clamped).rounded())
        return ordered[index]
    }

    static func zeroCrossingRate(_ samples: [Float]) -> Double {
        guard samples.count > 1 else { return 0 }
        let crossings = zip(samples.dropFirst(), samples).reduce(0) { partial, pair in
            partial + ((pair.0 >= 0 && pair.1 < 0) || (pair.0 < 0 && pair.1 >= 0) ? 1 : 0)
        }
        return Double(crossings) / Double(samples.count - 1)
    }

    static func computeFFTMagnitudes(frame: [Float]) -> [Float] {
        guard !frame.isEmpty else { return [] }

        let fftSize = 1 << Int(ceil(log2(Double(max(2, frame.count)))))
        let halfSize = fftSize / 2
        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var padded = Array(repeating: Float.zero, count: fftSize)
        for index in frame.indices {
            padded[index] = frame[index]
        }

        var window = Array(repeating: Float.zero, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        var windowed = Array(repeating: Float.zero, count: fftSize)
        vDSP_vmul(padded, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        var real = Array(repeating: Float.zero, count: halfSize)
        var imag = Array(repeating: Float.zero, count: halfSize)
        var magnitudes = Array(repeating: Float.zero, count: halfSize)

        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                var splitComplex = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { paddedBuffer in
                    paddedBuffer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexBuffer in
                        vDSP_ctoz(complexBuffer, 2, &splitComplex, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        return magnitudes
    }
}
