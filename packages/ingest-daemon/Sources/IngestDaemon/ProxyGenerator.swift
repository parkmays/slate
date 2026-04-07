// SLATE — ProxyGenerator
// Owned by: Claude Code
//
// VideoToolbox-based proxy generation. Creates 1/4 resolution H.264 proxies
// suitable for web streaming and editing in NLEs.
//
// Target: < 6 min for 1-hour ProRes on M4 Max
// Output: ~/Movies/SLATE/{project}/Proxies/{clipId}.mp4 + .m3u8

import Foundation
@preconcurrency import AVFoundation
import VideoToolbox
import GRDB
import SLATESharedTypes
import CryptoKit

// Reader/writer objects are used only on their dedicated serial queues.
private final class VideoEncodeState: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput
    let lut: ProxyLUT
    let customCubeURL: URL?
    let clipId: String
    let totalFrames: Int
    let clip: Clip
    let burnInConfig: BurnInConfig
    let proxyWidth: Int
    let proxyHeight: Int
    var frameCount = 0
    var finished = false

    init(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput,
        lut: ProxyLUT,
        customCubeURL: URL?,
        clipId: String,
        totalFrames: Int,
        clip: Clip,
        burnInConfig: BurnInConfig,
        proxyWidth: Int,
        proxyHeight: Int
    ) {
        self.output = output
        self.input = input
        self.lut = lut
        self.customCubeURL = customCubeURL
        self.clipId = clipId
        self.totalFrames = totalFrames
        self.clip = clip
        self.burnInConfig = burnInConfig
        self.proxyWidth = proxyWidth
        self.proxyHeight = proxyHeight
    }
}

private final class AudioEncodeState: @unchecked Sendable {
    let output: AVAssetReaderTrackOutput
    let input: AVAssetWriterInput
    var finished = false

    init(output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
        self.output = output
        self.input = input
    }
}

public actor ProxyGenerator {
    struct ForensicWatermarkHook: Codable, Sendable {
        let clipId: String
        let projectId: String
        let seed: String
        let generatedAt: String
        let method: String
    }

    private static func resolveProxyLUT(for clip: Clip) -> (ProxyLUT, URL?) {
        if clip.proxyLUT == "custom_cube", let path = clip.customProxyLUTPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            return (.customCube, URL(fileURLWithPath: path))
        }
        if let raw = clip.proxyLUT, let pl = ProxyLUT(rawValue: raw) {
            return (pl, nil)
        }
        return (LUTManager.lut(for: clip.sourceFormat), nil)
    }

    private let dbQueue: DatabaseQueue
    /// Must be the same `GRDBStore` instance as the ingest pipeline so R2 completion updates the correct database (not `GRDBStore.shared` when using a custom DB path).
    private let grdbStore: GRDBStore
    private let r2Uploader = R2Uploader()
    private var processingQueue: [String: Task<Void, Error>] = [:]

    public init(dbQueue: DatabaseQueue, grdbStore: GRDBStore) {
        self.dbQueue = dbQueue
        self.grdbStore = grdbStore
    }
    
    /// Generate proxy for a clip
    public func generateProxy(
        for clip: Clip,
        burnInConfig: BurnInConfig = BurnInConfig(),
        uploadThrottleBytesPerSecond: Int? = nil,
        transcodeProfile: ProxyTranscodeProfile? = nil
    ) async throws {
        // Skip if already processing
        if processingQueue[clip.id] != nil {
            return
        }
        
        let task = Task {
            defer { processingQueue.removeValue(forKey: clip.id) }
            try await performProxyGeneration(
                clip: clip,
                burnInConfig: burnInConfig,
                uploadThrottleBytesPerSecond: uploadThrottleBytesPerSecond,
                transcodeProfile: transcodeProfile
            )
        }
        
        processingQueue[clip.id] = task
        try await task.value
    }
    
    private func performProxyGeneration(
        clip: Clip,
        burnInConfig: BurnInConfig,
        uploadThrottleBytesPerSecond: Int?,
        transcodeProfile: ProxyTranscodeProfile?
    ) async throws {
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
        let (selectedLUT, customCubeURL) = Self.resolveProxyLUT(for: clip)
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
            let profile = transcodeProfile ?? .slateDefault
            let scaleDivisor = max(profile.scaleDivisor, 1)
            let proxyWidth  = max((displayWidth  / scaleDivisor) & ~1, 640)
            let proxyHeight = max((displayHeight / scaleDivisor) & ~1, 360)
            
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
                    AVVideoAverageBitRateKey: profile.bitrateBps,
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
            if audioTrack != nil {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 48000,
                    AVEncoderBitRateKey: 128_000
                ]
                
                let writerAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                writerAudioInput.expectsMediaDataInRealTime = false
                writer.add(writerAudioInput)
                audioInput = writerAudioInput
            }
            
            // Start reader and writer
            guard writer.startWriting() else {
                throw ProxyError.writingFailed(writer.error?.localizedDescription ?? "Failed to start AVAssetWriter")
            }
            guard reader.startReading() else {
                throw ProxyError.writingFailed(reader.error?.localizedDescription ?? "Failed to start AVAssetReader")
            }
            writer.startSession(atSourceTime: .zero)
            
            // Process video frames (mutable state lives in @unchecked Sendable boxes; each queue is serial).
            let duration = try await asset.load(.duration)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let totalFrames = max(
                Int(CMTimeGetSeconds(duration) * Double(nominalFrameRate)),
                1
            )
            
            let processingGroup = DispatchGroup()
            let videoQueue = DispatchQueue(label: "com.slate.proxy.video")
            let audioQueue = DispatchQueue(label: "com.slate.proxy.audio")
            
            // Video processing (box AV objects before the queue; closure only captures Sendable boxes).
            let videoState = VideoEncodeState(
                output: videoOutput,
                input: videoInput,
                lut: selectedLUT,
                customCubeURL: customCubeURL,
                clipId: clip.id,
                totalFrames: totalFrames,
                clip: clip,
                burnInConfig: burnInConfig,
                proxyWidth: proxyWidth,
                proxyHeight: proxyHeight
            )
            processingGroup.enter()
            // Must only append when `isReadyForMoreMediaData` is true; otherwise AVAssetWriterInput can throw (abort).
            videoInput.requestMediaDataWhenReady(on: videoQueue) { [videoState] in
                let state = videoState
                while state.input.isReadyForMoreMediaData, !state.finished {
                    autoreleasepool {
                        guard let sampleBuffer = state.output.copyNextSampleBuffer() else {
                            state.finished = true
                            state.input.markAsFinished()
                            processingGroup.leave()
                            return
                        }
                        let processedBuffer = LUTManager.applyProxyLUT(
                            to: sampleBuffer,
                            lut: state.lut,
                            customCubeURL: state.customCubeURL
                        ) ?? sampleBuffer
                        var bufferToAppend = processedBuffer
                        if state.burnInConfig.enabled,
                           let pb = CMSampleBufferGetImageBuffer(bufferToAppend) {
                            let renderer = BurnInRenderer()
                            let tc = renderer.timecodeString(
                                startTC: state.clip.sourceTimecodeStart,
                                frameNumber: state.frameCount,
                                fps: state.clip.sourceFps
                            )
                            let meta = ProxyGenerator.buildMetadataLine(clip: state.clip)
                            if let burned = renderer.renderBurnIn(
                                pixelBuffer: pb,
                                timecodeString: tc,
                                metadataLine: meta,
                                config: state.burnInConfig,
                                outputWidth: state.proxyWidth,
                                outputHeight: state.proxyHeight
                            ),
                               let rebuilt = LUTManager.sampleBuffer(wrapping: burned, timingFrom: bufferToAppend) {
                                bufferToAppend = rebuilt
                            }
                        }
                        guard state.input.append(bufferToAppend) else {
                            print("Failed to append video sample")
                            state.finished = true
                            state.input.markAsFinished()
                            processingGroup.leave()
                            return
                        }
                        state.frameCount += 1
                        // Reader-reported frame count can exceed nominal duration*fps by a frame; clamp for UI/logging.
                        let progress = min(Double(state.frameCount) / Double(state.totalFrames), 1.0)
                        print("Proxy progress for \(state.clipId): \(progress * 100)%")
                    }
                }
            }
            
            // Audio processing
            if let audioOutput = audioOutput, let audioWriterInput = audioInput {
                let audioState = AudioEncodeState(output: audioOutput, input: audioWriterInput)
                processingGroup.enter()
                audioWriterInput.requestMediaDataWhenReady(on: audioQueue) { [audioState] in
                    let state = audioState
                    while state.input.isReadyForMoreMediaData, !state.finished {
                        autoreleasepool {
                            guard let sampleBuffer = state.output.copyNextSampleBuffer() else {
                                state.finished = true
                                state.input.markAsFinished()
                                processingGroup.leave()
                                return
                            }
                            guard state.input.append(sampleBuffer) else {
                                print("Failed to append audio sample")
                                state.finished = true
                                state.input.markAsFinished()
                                processingGroup.leave()
                                return
                            }
                        }
                    }
                }
            }
            
            // Wait for completion (async-safe vs DispatchGroup.wait)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                processingGroup.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                    continuation.resume()
                }
            }
            
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
            
            // Update database
            try await updateClipAfterProxyGeneration(
                clipId: clip.id,
                proxyPath: proxyURL.path,
                proxyChecksum: proxyChecksum,
                proxyLUT: selectedLUT.rawValue,
                proxyColorSpace: proxyColorSpace
            )

            try await writeForensicWatermarkHook(clip: clip, proxyURL: proxyURL)

            await uploadProxyToR2(
                clip: clip,
                proxyURL: proxyURL,
                playlistURL: playlistURL,
                uploadThrottleBytesPerSecond: uploadThrottleBytesPerSecond
            )

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
        playlist += "#EXT-X-TARGETDURATION:\(Int(durationSeconds))\n"
        playlist += "#EXT-X-MEDIA-SEQUENCE:0\n"
        playlist += "#EXTINF:\(String(format: "%.3f", durationSeconds)),\n"
        playlist += videoURL.lastPathComponent + "\n"
        playlist += "#EXT-X-ENDLIST\n"
        
        try playlist.write(to: playlistURL, atomically: true, encoding: .utf8)
    }
    
    private func updateClipStatus(clipId: String, status: ProxyStatus) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET proxy_status = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: [status.rawValue, now, clipId]
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
        proxyLUT: String,
        proxyColorSpace: String
    ) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET proxy_status = ?,
                        proxy_path = ?,
                        proxy_checksum = ?,
                        proxy_lut = ?,
                        proxy_color_space = ?,
                        updated_at = ?
                    WHERE id = ?
                """,
                arguments: [
                    ProxyStatus.ready.rawValue,
                    proxyPath,
                    proxyChecksum,
                    proxyLUT,
                    proxyColorSpace,
                    now,
                    clipId
                ]
            )
        }
    }

    private func writeForensicWatermarkHook(clip: Clip, proxyURL: URL) async throws {
        let seedInput = "\(clip.id):\(clip.projectId):\(Date().timeIntervalSince1970)"
        let digest = SHA256.hash(data: Data(seedInput.utf8))
        let seed = digest.map { String(format: "%02x", $0) }.joined()
        let payload = ForensicWatermarkHook(
            clipId: clip.id,
            projectId: clip.projectId,
            seed: seed,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            method: "hook_v1"
        )
        let sidecarURL = proxyURL.deletingPathExtension().appendingPathExtension("watermark.json")
        let data = try JSONEncoder().encode(payload)
        try data.write(to: sidecarURL, options: .atomic)
    }
    
    /// Uploads proxy MP4, HLS playlist, and thumbnail to Cloudflare R2. Failures are logged; local `ready` proxy remains valid.
    private func uploadProxyToR2(
        clip: Clip,
        proxyURL: URL,
        playlistURL: URL,
        uploadThrottleBytesPerSecond: Int?
    ) async {
        guard R2Credentials.loadFromKeychain() != nil else {
            print("[ProxyGenerator] R2 Keychain credentials not found; skipping remote upload for \(clip.id)")
            return
        }

        do {
            try await updateClipStatus(clipId: clip.id, status: .uploading)
        } catch {
            print("[ProxyGenerator] Could not set proxy_status to uploading for \(clip.id): \(error)")
            return
        }

        let prefix = "\(clip.projectId)/\(clip.id)"
        let mp4Key = "\(prefix)/proxy.mp4"
        let m3u8Key = "\(prefix)/proxy.m3u8"
        let thumbKey = "\(prefix)/proxy_thumb.jpg"

        let publicMP4: String
        do {
            publicMP4 = try await r2Uploader.upload(
                localURL: proxyURL,
                r2Key: mp4Key,
                contentType: "video/mp4",
                throttleBytesPerSecond: uploadThrottleBytesPerSecond
            )
            _ = try await r2Uploader.upload(
                localURL: playlistURL,
                r2Key: m3u8Key,
                contentType: "application/x-mpegURL",
                throttleBytesPerSecond: uploadThrottleBytesPerSecond
            )

            let thumbURL = try await r2Uploader.generateThumbnail(proxyURL: proxyURL)
            defer { try? FileManager.default.removeItem(at: thumbURL) }
            _ = try await r2Uploader.upload(
                localURL: thumbURL,
                r2Key: thumbKey,
                contentType: "image/jpeg",
                throttleBytesPerSecond: uploadThrottleBytesPerSecond
            )
        } catch {
            print("[ProxyGenerator] R2 upload failed for \(clip.id): \(error)")
            do {
                try await updateClipStatus(clipId: clip.id, status: .ready)
            } catch {
                print("[ProxyGenerator] Could not restore proxy_status to ready after R2 failure: \(error)")
            }
            return
        }

        do {
            try await grdbStore.markProxyUploaded(clipId: clip.id, publicURL: publicMP4)
        } catch {
            print("[ProxyGenerator] R2 objects uploaded but GRDB markProxyUploaded failed for \(clip.id): \(error)")
        }
    }

    /// Narrative: slate-style scene / shot / take / camera line. Documentary: subject + session.
    private nonisolated static func buildMetadataLine(clip: Clip) -> String {
        switch clip.projectMode {
        case .narrative:
            guard let n = clip.narrativeMeta else { return "" }
            return "SC: \(n.sceneNumber)  SH: \(n.shotCode)  TK: \(n.takeNumber)  CAM: \(n.cameraId)"
        case .documentary:
            guard let d = clip.documentaryMeta else { return "" }
            return "SUBJECT: \(d.subjectName) — \(d.sessionLabel)"
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