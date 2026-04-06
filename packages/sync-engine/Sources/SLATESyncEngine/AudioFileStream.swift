import AVFoundation
import Foundation

/// Streaming audio file processor for memory-efficient handling of large files
public actor AudioFileStream {
    
    public struct Chunk: Sendable {
        public let samples: [Float]
        public let sampleRate: Double
        public let timestamp: TimeInterval
        public let isFinal: Bool
        
        public init(samples: [Float], sampleRate: Double, timestamp: TimeInterval, isFinal: Bool = false) {
            self.samples = samples
            self.sampleRate = sampleRate
            self.timestamp = timestamp
            self.isFinal = isFinal
        }
    }
    
    public enum StreamError: Error, LocalizedError {
        case fileNotFound(URL)
        case unsupportedFormat(String)
        case readFailed(Error)
        case invalidAudioData
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "Audio file not found: \(url.path)"
            case .unsupportedFormat(let format):
                return "Unsupported audio format: \(format)"
            case .readFailed(let error):
                return "Failed to read audio file: \(error.localizedDescription)"
            case .invalidAudioData:
                return "Invalid audio data in file"
            }
        }
    }
    
    private let url: URL
    private let chunkSize: Int
    private let asset: AVURLAsset
    private let reader: AVAssetReader
    private let trackOutput: AVAssetReaderTrackOutput
    /// Cached from `load(.naturalTimeScale)` (replaces deprecated direct property access).
    private let pcmSampleRate: Double
    /// Cached from `load(.duration)`.
    private let durationSeconds: TimeInterval
    
    /// Initialize audio file stream
    /// - Parameters:
    ///   - url: URL of the audio file
    ///   - chunkSize: Number of samples per chunk (default: 48000 = 1 second at 48kHz)
    public init(url: URL, chunkSize: Int = 48000) async throws {
        self.url = url
        self.chunkSize = chunkSize
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StreamError.fileNotFound(url)
        }
        
        self.asset = AVURLAsset(url: url)
        
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else {
            throw StreamError.unsupportedFormat("No audio track found")
        }
        
        let naturalTimeScale = try await audioTrack.load(.naturalTimeScale)
        let loadedDuration = try await asset.load(.duration)
        self.durationSeconds = CMTimeGetSeconds(loadedDuration)
        self.pcmSampleRate = Double(naturalTimeScale)
        
        self.reader = try AVAssetReader(asset: asset)
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMBitDepthKey: 32,
            AVSampleRateKey: naturalTimeScale
        ]
        
        self.trackOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: outputSettings
        )
        
        reader.add(trackOutput)
    }
    
    /// Stream audio data in chunks
    /// - Returns: Async stream of audio chunks
    public func stream() throws -> AsyncThrowingStream<Chunk, Error> {
        // Start reading
        guard reader.startReading() else {
            throw StreamError.readFailed(NSError(domain: "AudioFileStream", code: -1))
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                var sampleCount = 0
                let sampleRate = pcmSampleRate
                
                while reader.status == .reading {
                        guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
                              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                            continue
                        }
                        
                        // Get audio data from buffer
                        var lengthAtOffset = 0
                        var totalLength = 0
                        var dataPointer: UnsafeMutablePointer<Int8>?
                        let status = CMBlockBufferGetDataPointer(
                            blockBuffer,
                            atOffset: 0,
                            lengthAtOffsetOut: &lengthAtOffset,
                            totalLengthOut: &totalLength,
                            dataPointerOut: &dataPointer
                        )

                        let length = lengthAtOffset > 0 ? lengthAtOffset : totalLength
                        guard status == noErr, let pointer = dataPointer, length > 0 else {
                            continuation.finish(throwing: StreamError.invalidAudioData)
                            return
                        }
                        
                        // Convert to float array
                        let floatCount = length / MemoryLayout<Float>.size
                        let samples = pointer.withMemoryRebound(to: Float.self, capacity: floatCount) { fp in
                            Array(UnsafeBufferPointer(start: fp, count: floatCount))
                        }
                        
                        // Create chunk
                        let chunk = Chunk(
                            samples: samples,
                            sampleRate: sampleRate,
                            timestamp: Double(sampleCount) / sampleRate
                        )
                        
                        sampleCount += samples.count
                        
                        // Check if this is the final chunk
                        if reader.status == .completed {
                            var finalChunk = chunk
                            finalChunk = Chunk(
                                samples: chunk.samples,
                                sampleRate: chunk.sampleRate,
                                timestamp: chunk.timestamp,
                                isFinal: true
                            )
                            continuation.yield(finalChunk)
                            break
                        }
                        
                        continuation.yield(chunk)
                    }
                    
                    if let error = reader.error {
                        continuation.finish(throwing: StreamError.readFailed(error))
                    } else {
                        continuation.finish()
                    }
            }
        }
    }
    
    /// Get total duration of the audio file
    public var duration: TimeInterval {
        durationSeconds
    }
    
    /// Get sample rate of the audio file
    public var sampleRate: Double {
        pcmSampleRate
    }
    
    /// Get total number of samples
    public var totalSamples: Int {
        return Int(duration * sampleRate)
    }
}

/// Streaming audio processor for memory-efficient operations
public actor StreamingAudioProcessor {
    
    private let maxMemoryUsage: Int // Maximum samples to keep in memory
    private var processedChunks: [AudioFileStream.Chunk] = []
    
    public init(maxMemoryUsage: Int = 10_000_000) { // 10 million samples ~ 40MB
        self.maxMemoryUsage = maxMemoryUsage
    }
    
    /// Process audio file with streaming
    /// - Parameters:
    ///   - url: Audio file URL
    ///   - processor: Closure to process each chunk
    public func processStreaming(
        url: URL,
        processor: @escaping (AudioFileStream.Chunk) async throws -> Void
    ) async throws {
        let stream = try await AudioFileStream(url: url)
        let chunkStream = try await stream.stream()

        do {
            for try await chunk in chunkStream {
                // Process chunk
                try await processor(chunk)
                
                // Manage memory
                processedChunks.append(chunk)
                let totalSamples = processedChunks.reduce(0) { $0 + $1.samples.count }
                
                if totalSamples > maxMemoryUsage {
                    // Release oldest chunks
                    let samplesToRemove = totalSamples - maxMemoryUsage + chunk.samples.count
                    var removed = 0
                    processedChunks = processedChunks.filter { chunk in
                        if removed >= samplesToRemove {
                            return true
                        }
                        removed += chunk.samples.count
                        return false
                    }
                }
            }
        } catch {
            throw error
        }
    }
    
    /// Calculate RMS energy with streaming
    public func calculateStreamingRMS(url: URL) async throws -> Float {
        var sumSquares: Float = 0
        var totalSamples: Int = 0
        
        try await processStreaming(url: url) { chunk in
            let chunkSumSquares = chunk.samples.reduce(0) { $0 + $1 * $1 }
            sumSquares += chunkSumSquares
            totalSamples += chunk.samples.count
        }
        
        guard totalSamples > 0 else { return 0 }
        return sqrt(sumSquares / Float(totalSamples))
    }
    
    /// Downsample with streaming
    public func downsampleStreaming(
        url: URL,
        from sourceRate: Double,
        to targetRate: Double
    ) async throws -> [Float] {
        guard sourceRate > targetRate else {
            // Load entire file if no downsampling needed
            let stream = try await AudioFileStream(url: url)
            var allSamples: [Float] = []
            for try await chunk in try await stream.stream() {
                allSamples.append(contentsOf: chunk.samples)
            }
            return allSamples
        }
        
        let decimationFactor = Int(sourceRate / targetRate)
        guard decimationFactor > 1 else { return [] }
        
        var downsampled: [Float] = []
        
        try await processStreaming(url: url) { chunk in
            let chunkDownsampled = AudioAnalysisOptimized.downsample(
                chunk.samples,
                from: sourceRate,
                to: targetRate
            )
            downsampled.append(contentsOf: chunkDownsampled)
        }
        
        return downsampled
    }
    
    /// Perform correlation with streaming
    public func correlateStreaming(
        primaryURL: URL,
        secondaryURL: URL,
        maxLag: Int
    ) async throws -> (lag: Int, score: Float) {
        // For correlation, we need the full signals
        // Use streaming to manage memory during loading
        let primary = try await downsampleStreaming(
            url: primaryURL,
            from: 48000, // Assume 48kHz, should read from file
            to: 8000     // Downsample to 8kHz for correlation
        )
        
        let secondary = try await downsampleStreaming(
            url: secondaryURL,
            from: 48000,
            to: 8000
        )
        
        // Use optimized correlation
        return AudioAnalysisOptimized.fastCorrelation(
            reference: primary,
            comparison: secondary,
            maxLag: maxLag
        )
    }
}

// MARK: - AudioFileLoader Extension

extension AudioFileLoader {
    
    /// Load mono samples with streaming for large files
    public static func loadMonoSamplesStreaming(
        from url: URL,
        limitSeconds: Double? = nil,
        maxMemoryUsage: Int = 10_000_000
    ) async throws -> (samples: [Float], sampleRate: Double) {
        _ = maxMemoryUsage
        let stream = try await AudioFileStream(url: url)
        let sampleRateForLimit = await stream.sampleRate
        let limitSamples = limitSeconds.map { Int($0 * sampleRateForLimit) } ?? Int.max

        var allSamples: [Float] = []
        var collectedSamples = 0

        for try await chunk in try await stream.stream() {
            let remainingSamples = limitSamples - collectedSamples
            if remainingSamples <= 0 {
                break
            }
            
            let samplesToTake = min(chunk.samples.count, remainingSamples)
            allSamples.append(contentsOf: Array(chunk.samples.prefix(samplesToTake)))
            collectedSamples += samplesToTake
            
            if chunk.isFinal || collectedSamples >= limitSamples {
                break
            }
        }
        
        return (allSamples, sampleRateForLimit)
    }
}
