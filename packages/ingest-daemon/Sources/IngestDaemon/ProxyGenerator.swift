// SLATE — ProxyGenerator
// Owned by: Claude Code
//
// VideoToolbox-based proxy generation. Creates 1/4 resolution H.264 proxies
// suitable for web streaming and editing in NLEs.
//
// Target: < 6 min for 1-hour ProRes on M4 Max
// Output: ~/Movies/SLATE/{project}/Proxies/{clipId}.mp4 + .m3u8

import Foundation
import AVFoundation
import VideoToolbox
import GRDB
import SLATEAIPipeline
import SLATESharedTypes

public actor ProxyGenerator {
    private let dbQueue: DatabaseQueue
    private var processingQueue: [String: Task<Void, Error>] = [:]
    
    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    /// Generate proxy for a clip
    public func generateProxy(for clip: Clip) async throws {
        // Skip if already processing
        if processingQueue[clip.id] != nil {
            return
        }
        
        let task = Task {
            defer { processingQueue.removeValue(forKey: clip.id) }
            try await performProxyGeneration(clip: clip)
        }
        
        processingQueue[clip.id] = task
        try await task.value
    }
    
    private func performProxyGeneration(clip: Clip) async throws {
        let sourceURL = URL(fileURLWithPath: clip.sourcePath)
        let proxyDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Movies/SLATE")
            .appendingPathComponent(clip.projectId)
            .appendingPathComponent("Proxies")
        
        try FileManager.default.createDirectory(at: proxyDir, withIntermediateDirectories: true)
        
        let proxyURL = proxyDir.appendingPathComponent("\(clip.id).mp4")
        let playlistURL = proxyDir.appendingPathComponent("\(clip.id).m3u8")
        
        // Determine viewing LUT for this clip's source format.
        // Log-encoded formats (ARRIRAW, BRAW, R3D) get a Rec.709 viewing LUT baked in.
        // ProRes / H.264 / MXF are already Rec.709 — pass-through.
        let selectedLUT = LUTManager.lut(for: clip.sourceFormat)
        let proxyColorSpace = selectedLUT.proxyColorSpace   // "rec709" or "log"

        // Update status to processing
        try await updateClipStatus(clipId: clip.id, status: .processing)

        do {
            // Create AVAssetReader
            let asset = AVAsset(url: sourceURL)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ProxyError.noVideoTrack
            }
            
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            
            // Get source dimensions and rotation transform
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)

            // Apply the track's preferred transform to get the correctly oriented display size.
            // Cameras that shoot portrait or were mounted sideways have a non-identity transform.
            // We render into the transformed (display) size so the proxy is already right-side-up.
            let transformedSize = naturalSize.applying(preferredTransform)
            let displayWidth  = Int(abs(transformedSize.width))
            let displayHeight = Int(abs(transformedSize.height))

            // Ensure dimensions are even (required by H.264 encoder) and at least 640×360.
            let proxyWidth  = max((displayWidth  / 4) & ~1, 640)
            let proxyHeight = max((displayHeight / 4) & ~1, 360)
            
            // Create reader
            let reader = try AVAssetReader(asset: asset)
            
            // Video output
            let videoOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: proxyWidth,
                    kCVPixelBufferHeightKey as String: proxyHeight
                ]
            )
            reader.add(videoOutput)
            
            // Audio output (if present)
            var audioOutput: AVAssetReaderTrackOutput?
            if let audioTrack = audioTrack {
                audioOutput = AVAssetReaderTrackOutput(
                    track: audioTrack,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                )
                if let audioOutput = audioOutput {
                    reader.add(audioOutput)
                }
            }
            
            // Create writer
            let writer = try AVAssetWriter(outputURL: proxyURL, fileType: .mp4)
            
            // Video input
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: proxyWidth,
                AVVideoHeightKey: proxyHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000, // 8 Mbps
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: clip.sourceFps,
                    AVVideoMaxKeyFrameIntervalKey: Int(clip.sourceFps * 2) // Every 2 seconds
                ]
            ]
            
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = false
            // Embed the rotation so the proxy plays back correctly in every player.
            // The transform maps from natural (camera) coordinates to display coordinates.
            videoInput.transform = preferredTransform
            writer.add(videoInput)
            
            // Audio input (if present)
            var audioInput: AVAssetWriterInput?
            if let audioTrack = audioTrack {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 48000,
                    AVEncoderBitRateKey: 128_000
                ]
                
                audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput?.expectsMediaDataInRealTime = false
                if let audioInput = audioInput {
                    writer.add(audioInput)
                }
            }
            
            // Start reader and writer
            writer.startWriting()
            reader.startReading()
            writer.startSession(atSourceTime: .zero)
            
            // Process video frames
            var frameCount = 0
            var totalFrames = 0
            let duration = try await asset.load(.duration)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            totalFrames = Int(CMTimeGetSeconds(duration) * nominalFrameRate)
            
            var videoCompleted = false
            var audioCompleted = audioTrack == nil
            
            let processingGroup = DispatchGroup()
            let videoQueue = DispatchQueue(label: "video.queue")
            let audioQueue = DispatchQueue(label: "audio.queue")
            
            // Video processing
            processingGroup.enter()
            videoQueue.async {
                while !videoCompleted {
                    autoreleasepool {
                        if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
                            // Apply the appropriate viewing LUT (nil → pass-through, keep original).
                            let processedBuffer = LUTManager.applyProxyLUT(to: sampleBuffer, lut: selectedLUT) ?? sampleBuffer
                            
                            if !videoInput.append(processedBuffer) {
                                print("Failed to append video sample")
                            }
                            frameCount += 1
                            
                            // Update progress
                            Task {
                                let progress = Double(frameCount) / Double(totalFrames)
                                try? await self.updateProxyProgress(clipId: clip.id, progress: progress)
                            }
                        } else {
                            videoCompleted = true
                            videoInput.markAsFinished()
                            processingGroup.leave()
                        }
                    }
                }
            }
            
            // Audio processing
            if let audioOutput = audioOutput, let audioInput = audioInput {
                processingGroup.enter()
                audioQueue.async {
                    var audioCompleted = false
                    while !audioCompleted {
                        autoreleasepool {
                            if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                                if !audioInput.append(sampleBuffer) {
                                    print("Failed to append audio sample")
                                }
                            } else {
                                audioCompleted = true
                                audioInput.markAsFinished()
                                processingGroup.leave()
                            }
                        }
                    }
                }
            }
            
            // Wait for completion
            processingGroup.wait()
            
            // Finish writing
            await writer.finishWriting()
            
            // Check for errors
            if writer.status == .failed {
                throw ProxyError.writingFailed(writer.error?.localizedDescription ?? "Unknown error")
            }
            
            // Compute proxy checksum
            let proxyChecksum = try ChecksumUtil.sha256(fileURL: proxyURL)
            
            // Generate HLS playlist
            try await generateHLSPlaylist(
                videoURL: proxyURL,
                playlistURL: playlistURL,
                duration: duration,
                proxyWidth: proxyWidth,
                proxyHeight: proxyHeight
            )
            
            // Canonical R2 key — must match storage.md convention: {projectId}/{clipId}/proxy.mp4
            let canonicalR2Key = "\(clip.projectId)/\(clip.id)/proxy.mp4"

            // Update database
            try await updateClipAfterProxyGeneration(
                clipId: clip.id,
                proxyPath: proxyURL.path,
                proxyChecksum: proxyChecksum,
                proxyR2Key: canonicalR2Key,
                proxyLUT: selectedLUT.rawValue,
                proxyColorSpace: proxyColorSpace
            )
            
            // Trigger next steps
            await triggerSyncAndAI(clip: clip)
            
        } catch {
            // Update status to error
            try? await updateClipStatus(clipId: clip.id, status: .error)
            throw error
        }
    }
    
    private func generateHLSPlaylist(
        videoURL: URL,
        playlistURL: URL,
        duration: CMTime,
        proxyWidth: Int,
        proxyHeight: Int
    ) async throws {
        let durationSeconds = CMTimeGetSeconds(duration)
        
        var playlist = "#EXTM3U\n"
        playlist += "#EXT-X-VERSION:3\n"
        playlist += "#EXT-X-TARGETDURATION:\(Int(durationSeconds))\"
        playlist += "#EXT-X-MEDIA-SEQUENCE:0\n"
        playlist += "#EXTINF:\(String(format: "%.3f", durationSeconds)),\n"
        playlist += videoURL.lastPathComponent + "\n"
        playlist += "#EXT-X-ENDLIST\n"
        
        try playlist.write(to: playlistURL, atomically: true, encoding: .utf8)
    }
    
    private func updateClipStatus(clipId: String, status: ProxyStatus) async throws {
        try await dbQueue.write { db in
            try Clip.filter(Column("id") == clipId).updateAll(
                db,
                Column("proxy_status") <- status.rawValue,
                Column("updated_at") <- Date()
            )
        }
    }
    
    private func updateProxyProgress(clipId: String, progress: Double) async throws {
        // Could emit via socket or store in a progress table
        print("Proxy progress for \(clipId): \(progress * 100)%")
    }
    
    private func updateClipAfterProxyGeneration(
        clipId: String,
        proxyPath: String,
        proxyChecksum: String,
        proxyR2Key: String,
        proxyLUT: String,
        proxyColorSpace: String
    ) async throws {
        try await dbQueue.write { db in
            try Clip.filter(Column("id") == clipId).updateAll(
                db,
                Column("proxy_status")      <- ProxyStatus.ready.rawValue,
                Column("proxy_path")        <- proxyPath,
                Column("proxy_checksum")    <- proxyChecksum,
                Column("proxy_r2_key")      <- proxyR2Key,
                Column("proxy_lut")         <- proxyLUT,
                Column("proxy_color_space") <- proxyColorSpace,
                Column("proxy_generated_at") <- Date(),
                Column("updated_at")        <- Date()
            )
        }
    }
    
    private func triggerSyncAndAI(clip: Clip) async {
        // Fire AI scoring as a non-blocking background task.
        // The proxy file is on disk at this point, so the vision scorer can sample frames.
        // Errors are logged but do not fail the ingest — AI scores are advisory.
        Task.detached(priority: .background) {
            do {
                let scores = try await AIPipeline().scoreClip(clip)
                // Persist scores back to GRDB using a plain write so we stay off the actor.
                try await self.dbQueue.write { db in
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .sortedKeys
                    let scoresJSON = (try? encoder.encode(scores)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    let now = ISO8601DateFormatter().string(from: Date())
                    try db.execute(
                        sql: """
                            UPDATE clips
                            SET ai_scores = ?, ai_processing_status = 'ready', updated_at = ?
                            WHERE id = ?
                        """,
                        arguments: [scoresJSON, now, clip.id]
                    )
                }
                print("[ProxyGenerator] AI scoring complete for \(clip.id). Composite: \(scores.composite)")
            } catch {
                print("[ProxyGenerator] AI scoring failed for \(clip.id): \(error)")
            }
        }
    }
}

// MARK: - Proxy Errors

public enum ProxyError: Error, LocalizedError {
    case noVideoTrack
    case writingFailed(String)
    case compressionFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in source file"
        case .writingFailed(let message):
            return "Failed to write proxy: \(message)"
        case .compressionFailed(let error):
            return "Compression failed: \(error.localizedDescription)"
        }
    }
}

// ProxyStatus is defined in SLATESharedTypes/Clip.swift — no local redefinition needed.