import Foundation
import SLATESharedTypes

public struct SyncEngine: Sendable {
    private let configuration: SyncConfiguration

    public init(configuration: SyncConfiguration = .init()) {
        self.configuration = configuration
    }

    public func syncClip(videoURL: URL, audioFiles: [URL], fps: Double) async throws -> SyncResult {
        guard let primaryAudio = audioFiles.first else {
            return SyncResult(
                confidence: .manualRequired,
                method: .none,
                offsetFrames: 0
            )
        }

        do {
            if let timecodeResult = await attemptTimecodeSync(videoURL: videoURL, audioURL: primaryAudio, fps: fps) {
                return timecodeResult
            }

            if let slateOCRResult = try await attemptSlateOCRSync(videoURL: videoURL, audioURL: primaryAudio, fps: fps) {
                return slateOCRResult
            }

            if let clapResult = try await attemptClapSync(videoURL: videoURL, audioURL: primaryAudio, fps: fps) {
                return try await correctDrift(result: clapResult, videoURL: videoURL, audioURL: primaryAudio, fps: fps)
            }

            let correlationResult = try await fullFileCorrelation(videoURL: videoURL, audioURL: primaryAudio, fps: fps)
            return try await correctDrift(result: correlationResult, videoURL: videoURL, audioURL: primaryAudio, fps: fps)
        } catch {
            return SyncResult(
                confidence: .manualRequired,
                method: .none,
                offsetFrames: 0
            )
        }
    }

    // MARK: - Camera Group Sync (v1.2)

    /// Synchronises an entire camera group against the primary angle (A-cam).
    ///
    /// This is the high-level entry point used by IngestDaemon when it discovers
    /// that a set of clips share a `cameraGroupId`. It wraps `syncMultiCam` and
    /// returns the typed `CameraGroupSyncResult` that mirrors the contract schema.
    ///
    /// - Parameters:
    ///   - cameras: All angles for the group. The first element with `angle == .A`
    ///              is used as the sync primary. If no A-cam is present, the first
    ///              element is treated as primary.
    ///   - audioFiles: External audio files to include in sync (optional).
    ///   - fps: Frame rate shared by all cameras in the group.
    ///   - groupId: The UUID that ties these clips together (`Clip.cameraGroupId`).
    ///
    /// - Returns: A `CameraGroupSyncResult` with per-angle offsets and overall confidence.
    public func syncCameraGroup(
        cameras: [CameraInput],
        audioFiles: [URL] = [],
        fps: Double,
        groupId: String
    ) async throws -> CameraGroupSyncResult {
        guard !cameras.isEmpty else {
            return CameraGroupSyncResult(
                groupId: groupId,
                offsets: [],
                overallConfidence: .manualRequired,
                syncedAt: ISO8601DateFormatter().string(from: Date())
            )
        }

        // Designate A-cam as primary; fall back to first camera if none provided.
        let primary = cameras.first(where: { $0.angle == .A }) ?? cameras[0]
        let secondaries = cameras.filter { $0.url != primary.url }

        let multiCamResult = try await syncMultiCam(
            primaryCamera: primary.url,
            additionalCameras: secondaries.map(\.url),
            fps: fps,
            useSlateDetection: true
        )

        // Map CameraOffset (URL-keyed) back to the angle-keyed CameraGroupOffset.
        var groupOffsets: [CameraGroupOffset] = []
        for (index, camOffset) in multiCamResult.offsets.enumerated() {
            let matchingInput = secondaries.first(where: { $0.url == camOffset.cameraURL })
                ?? (index < secondaries.count ? secondaries[index] : nil)
            let angle = matchingInput?.angle ?? .B
            let clipId = matchingInput?.clipId
            groupOffsets.append(CameraGroupOffset(
                angle: angle,
                clipId: clipId,
                offsetFrames: camOffset.offsetFrames,
                offsetSeconds: camOffset.offsetSeconds,
                confidence: camOffset.confidence,
                method: camOffset.method
            ))
        }

        return CameraGroupSyncResult(
            groupId: groupId,
            primaryAngle: primary.angle,
            offsets: groupOffsets,
            overallConfidence: multiCamResult.overallConfidence,
            syncedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    public func syncMultiCam(
        primaryCamera: URL,
        additionalCameras: [URL],
        fps: Double,
        useSlateDetection: Bool = true
    ) async throws -> MultiCamSyncResult {
        var offsets: [CameraOffset] = []
        var notes: [String] = []
        var confidences: [Int] = []

        for secondaryCamera in additionalCameras {
            let offset = try await syncCameraPair(
                primary: primaryCamera,
                secondary: secondaryCamera,
                fps: fps,
                useSlateDetection: useSlateDetection
            )
            offsets.append(offset)
            confidences.append(offset.confidence.rank)
            notes.append("Camera \(secondaryCamera.lastPathComponent): offset \(offset.offsetFrames) frames (\(offset.method.rawValue))")
        }

        let overallConfidence: SyncConfidence
        if confidences.isEmpty {
            overallConfidence = .manualRequired
        } else {
            let minConfidence = confidences.min() ?? 0
            switch minConfidence {
            case 4:
                overallConfidence = .high
            case 3:
                overallConfidence = .medium
            case 2:
                overallConfidence = .low
            default:
                overallConfidence = .manualRequired
            }
        }

        return MultiCamSyncResult(
            primaryCamera: primaryCamera,
            offsets: offsets,
            overallConfidence: overallConfidence,
            notes: notes
        )
    }

    private func syncCameraPair(
        primary: URL,
        secondary: URL,
        fps: Double,
        useSlateDetection: Bool
    ) async throws -> CameraOffset {
        // 1. Try timecode metadata first
        do {
            if let timecodeOffset = try await attemptTimecodeMetadataSync(
                primary: primary,
                secondary: secondary,
                fps: fps
            ) {
                return timecodeOffset
            }
        } catch {
        }

        // 2. Try slate detection if enabled
        if useSlateDetection {
            do {
                if let slateOffset = try await attemptSlateDetectionSync(
                    primary: primary,
                    secondary: secondary,
                    fps: fps
                ) {
                    return slateOffset
                }
            } catch {
            }
        }

        // 3. Try audio correlation as fallback
        do {
            if let audioOffset = try await attemptAudioCorrelationSync(
                primary: primary,
                secondary: secondary,
                fps: fps
            ) {
                return audioOffset
            }
        } catch {
        }

        // 4. Manual fallback
        return CameraOffset(
            cameraURL: secondary,
            offsetFrames: 0,
            offsetSeconds: 0.0,
            confidence: .manualRequired,
            method: .manual
        )
    }

    private func attemptTimecodeMetadataSync(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> CameraOffset? {
        guard let primaryTC = await TimecodeMetadata.read(from: primary, fps: fps),
              let secondaryTC = await TimecodeMetadata.read(from: secondary, fps: fps)
        else {
            return nil
        }

        let deltaSeconds = secondaryTC.startSeconds - primaryTC.startSeconds
        let deltaFrames = Int((deltaSeconds * fps).rounded())

        return CameraOffset(
            cameraURL: secondary,
            offsetFrames: deltaFrames,
            offsetSeconds: deltaSeconds,
            confidence: .high,
            method: .timecodeMetadata
        )
    }

    private func attemptSlateDetectionSync(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> CameraOffset? {
        guard let primarySlate = try await SlateOCRDetector.detectVideoStartTimecode(in: primary, fps: fps),
              let secondarySlate = try await SlateOCRDetector.detectVideoStartTimecode(in: secondary, fps: fps)
        else {
            return nil
        }

        let deltaSeconds = secondarySlate.clipStartSeconds - primarySlate.clipStartSeconds
        let deltaFrames = Int((deltaSeconds * fps).rounded())
        let confidence: SyncConfidence = secondarySlate.confidence >= 0.55 ? .high : .medium

        return CameraOffset(
            cameraURL: secondary,
            offsetFrames: deltaFrames,
            offsetSeconds: deltaSeconds,
            confidence: confidence,
            method: .slateDetection
        )
    }

    private func attemptAudioCorrelationSync(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> CameraOffset? {
        let audioLoadStart = CFAbsoluteTimeGetCurrent()
        let primaryAudio = try await AudioFileLoader.loadMonoSamples(from: primary)
        let secondaryAudio = try await AudioFileLoader.loadMonoSamples(from: secondary)
        let audioLoadTime = CFAbsoluteTimeGetCurrent() - audioLoadStart
        
        let correlationStart = CFAbsoluteTimeGetCurrent()
        let primarySamples = primaryAudio.samples.map { abs($0) }
        let secondarySamples = secondaryAudio.samples.map { abs($0) }

        // Use optimized downsampling
        let coarseReference = AudioAnalysisOptimized.downsample(primarySamples, from: primaryAudio.sampleRate, to: configuration.coarseCorrelationRate)
        let coarseComparison = AudioAnalysisOptimized.downsample(secondarySamples, from: secondaryAudio.sampleRate, to: configuration.coarseCorrelationRate)
        let coarseMaxLag = Int(configuration.searchWindowSeconds * configuration.coarseCorrelationRate)
        
        // Use fast correlation for coarse search
        _ = AudioAnalysisOptimized.fastCorrelation(reference: coarseReference, comparison: coarseComparison, maxLag: coarseMaxLag)

        let fineReference = AudioAnalysisOptimized.downsample(primarySamples, from: primaryAudio.sampleRate, to: configuration.fineCorrelationRate)
        let fineComparison = AudioAnalysisOptimized.downsample(secondarySamples, from: secondaryAudio.sampleRate, to: configuration.fineCorrelationRate)

        // Use direct correlation for fine search (smaller search space)
        let fine = AudioAnalysis.bestLag(
            reference: fineReference,
            comparison: fineComparison,
            maxLag: Int(configuration.fineCorrelationRate)
        )
        
        let correlationTime = CFAbsoluteTimeGetCurrent() - correlationStart
        let totalTime = audioLoadTime + correlationTime
        let samplesProcessed = primarySamples.count + secondarySamples.count
        
        // Log performance metrics
        let metrics = SyncPerformanceMetrics(
            audioLoadTime: audioLoadTime,
            correlationTime: correlationTime,
            totalDuration: totalTime,
            samplesProcessed: samplesProcessed
        )
        
        print("Sync Performance: \(String(format: "%.2f", metrics.samplesPerSecond)) samples/sec, Total: \(String(format: "%.3f", totalTime))s")

        let offsetSeconds = Double(fine.lag) / configuration.fineCorrelationRate
        let offsetFrames = Int((offsetSeconds * fps).rounded())
        let confidence: SyncConfidence

        switch fine.score {
        case let score where score >= 0.70:
            confidence = .medium
        case let score where score >= 0.50:
            confidence = .low
        default:
            return nil
        }

        return CameraOffset(
            cameraURL: secondary,
            offsetFrames: offsetFrames,
            offsetSeconds: offsetSeconds,
            confidence: confidence,
            method: .audioCorrelation
        )
    }

    public func assignAudioRoles(tracks: [URL]) async -> [AudioTrack] {
        let classifier = AudioRoleClassifier()
        
        do {
            // Use the new classifier for all tracks
            let classifications = try await classifier.classifyRoles(trackURLs: tracks)
            
            var audioTracks: [AudioTrack] = []
            for (index, (url, classification)) in zip(tracks, classifications).enumerated() {
                let track = AudioTrack(
                    trackIndex: index,
                    role: .unknown, // Will be updated below
                    channelLabel: url.deletingPathExtension().lastPathComponent,
                    sampleRate: 48000, // Default, would be extracted from file
                    bitDepth: 32
                )
                
                let updatedTrack = classifier.updateTrack(track, with: classification)
                audioTracks.append(updatedTrack)
                
                print("Track \(index): \(classification.role.rawValue) (confidence: \(String(format: "%.2f", classification.confidence)))")
                print("  Reasoning: \(classification.reasoning)")
            }
            
            // Apply additional logic for multi-track scenarios
            return applyMultiTrackLogic(audioTracks)
            
        } catch {
            print("Audio role classification failed: \(error)")
            // Fall back to simple heuristic
            return await fallbackRoleAssignment(tracks: tracks)
        }
    }
    
    private func applyMultiTrackLogic(_ tracks: [AudioTrack]) -> [AudioTrack] {
        var updatedTracks = tracks
        
        // If we have multiple tracks, ensure we have at most one boom
        let boomTracks = tracks.filter { $0.role == .boom }
        if boomTracks.count > 1 {
            // Keep the loudest as boom, convert others to lav
            let loudestBoom = boomTracks.max { track1, track2 in
                // Would need RMS data here, using placeholder logic
                return track1.trackIndex < track2.trackIndex
            }
            
            for (index, track) in updatedTracks.enumerated() {
                if track.role == .boom && track.trackIndex != loudestBoom!.trackIndex {
                    updatedTracks[index] = AudioTrack(
                        trackIndex: track.trackIndex,
                        role: .lav,
                        channelLabel: track.channelLabel,
                        sampleRate: track.sampleRate,
                        bitDepth: track.bitDepth
                    )
                }
            }
        }
        
        // Ensure we have at most one mix track
        let mixTracks = updatedTracks.filter { $0.role == .mix }
        if mixTracks.count > 1 {
            // Keep the first as mix, convert others to iso
            for (index, track) in updatedTracks.enumerated() {
                if track.role == .mix && track.trackIndex != mixTracks.first!.trackIndex {
                    updatedTracks[index] = AudioTrack(
                        trackIndex: track.trackIndex,
                        role: .iso,
                        channelLabel: track.channelLabel,
                        sampleRate: track.sampleRate,
                        bitDepth: track.bitDepth
                    )
                }
            }
        }
        
        return updatedTracks
    }
    
    private func fallbackRoleAssignment(tracks: [URL]) async -> [AudioTrack] {
        // Original heuristic implementation as fallback
        var analyzed: [(index: Int, rms: Float, airiness: Float, track: AudioTrack)] = []

        for (index, url) in tracks.enumerated() {
            guard let loaded = try? await AudioFileLoader.loadMonoSamples(from: url, limitSeconds: 30) else {
                analyzed.append((
                    index,
                    0,
                    0,
                    AudioTrack(trackIndex: index, role: .unknown, channelLabel: url.deletingPathExtension().lastPathComponent, sampleRate: 0, bitDepth: 16)
                ))
                continue
            }

            let rms = AudioAnalysis.rms(loaded.samples)
            let diffs = zip(loaded.samples.dropFirst(), loaded.samples).map { abs($0.0 - $0.1) }
            let airiness = diffs.isEmpty ? 0 : AudioAnalysis.rms(diffs) / max(rms, 0.0001)
            let role: AudioTrackRole

            if rms < 0.01 {
                role = .unknown
            } else if airiness > 0.85 {
                role = .boom
            } else if rms > 0.05 {
                role = .lav
            } else {
                role = .mix
            }

            analyzed.append((
                index,
                rms,
                airiness,
                AudioTrack(
                    trackIndex: index,
                    role: role,
                    channelLabel: url.deletingPathExtension().lastPathComponent,
                    sampleRate: loaded.sampleRate,
                    bitDepth: 32
                )
            ))
        }

        if let loudest = analyzed.max(by: { $0.rms < $1.rms }),
           loudest.track.role != .boom,
           loudest.rms > 0.01,  // Only reassign if the track has actual audio
           let replaceIndex = analyzed.firstIndex(where: { $0.index == loudest.index }) {
            let replacement = AudioTrack(
                trackIndex: loudest.track.trackIndex,
                role: .boom,
                channelLabel: loudest.track.channelLabel,
                sampleRate: loudest.track.sampleRate,
                bitDepth: loudest.track.bitDepth
            )
            analyzed[replaceIndex] = (loudest.index, loudest.rms, loudest.airiness, replacement)
        }

        return analyzed.sorted { $0.index < $1.index }.map(\.track)
    }

    private func attemptTimecodeSync(videoURL: URL, audioURL: URL, fps: Double) async -> SyncResult? {
        guard let videoTimecode = await TimecodeMetadata.read(from: videoURL, fps: fps),
              let audioTimecode = await TimecodeMetadata.read(from: audioURL, fps: fps)
        else {
            return nil
        }

        let deltaSeconds = audioTimecode.startSeconds - videoTimecode.startSeconds
        let deltaFrames = Int((deltaSeconds * fps).rounded())
        return SyncResult(confidence: .high, method: .timecode, offsetFrames: deltaFrames)
    }

    private func attemptSlateOCRSync(videoURL: URL, audioURL: URL, fps: Double) async throws -> SyncResult? {
        guard let audioTimecode = await TimecodeMetadata.read(from: audioURL, fps: fps),
              let slateDetection = try await SlateOCRDetector.detectVideoStartTimecode(in: videoURL, fps: fps)
        else {
            return nil
        }

        let deltaSeconds = audioTimecode.startSeconds - slateDetection.clipStartSeconds
        let deltaFrames = Int((deltaSeconds * fps).rounded())
        let confidence: SyncConfidence = slateDetection.confidence >= 0.55 ? .high : .medium

        return SyncResult(
            confidence: confidence,
            method: .timecode,
            offsetFrames: deltaFrames,
            verifiedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func attemptClapSync(videoURL: URL, audioURL: URL, fps: Double) async throws -> SyncResult? {
        let video = try await AudioFileLoader.loadMonoSamples(from: videoURL, limitSeconds: configuration.clapSearchSeconds)
        let audio = try await AudioFileLoader.loadMonoSamples(from: audioURL, limitSeconds: configuration.clapSearchSeconds)

        let videoSamples = AudioAnalysis.downsample(video.samples, from: video.sampleRate, to: configuration.clapSampleRate)
        let audioSamples = AudioAnalysis.downsample(audio.samples, from: audio.sampleRate, to: configuration.clapSampleRate)
        let videoEnvelope = AudioAnalysis.onsetEnvelope(samples: videoSamples, sampleRate: configuration.clapSampleRate)
        let audioEnvelope = AudioAnalysis.onsetEnvelope(samples: audioSamples, sampleRate: configuration.clapSampleRate)

        guard !videoEnvelope.isEmpty, !audioEnvelope.isEmpty else { return nil }

        let hopSize = Int(configuration.clapSampleRate * 0.01)
        let peakWindow = max(1, Int(0.2 / 0.01))
        let videoPeaks = AudioAnalysis.topPeakIndices(values: videoEnvelope, count: 3, minSeparation: peakWindow)
        let audioPeaks = AudioAnalysis.topPeakIndices(values: audioEnvelope, count: 3, minSeparation: peakWindow)

        var bestCompositeScore: Float = 0
        var bestSNR: Float = 0
        var bestOffsetFrames = 0
        var bestClapTime: Double?

        let localWindowSamples = Int(configuration.clapSampleRate * 0.12)

        for videoPeak in videoPeaks {
            for audioPeak in audioPeaks {
                let videoCenter = videoPeak * hopSize
                let audioCenter = audioPeak * hopSize

                let rawVideoWindow = AudioAnalysis.slice(videoSamples, center: videoCenter, radius: localWindowSamples)
                let rawAudioWindow = AudioAnalysis.slice(audioSamples, center: audioCenter, radius: localWindowSamples)
                let videoNoiseFloor = AudioAnalysis.preRollNoiseFloor(
                    samples: videoSamples,
                    center: videoCenter,
                    sampleRate: configuration.clapSampleRate,
                    preRollSeconds: configuration.clapPreRollSeconds
                )
                let audioNoiseFloor = AudioAnalysis.preRollNoiseFloor(
                    samples: audioSamples,
                    center: audioCenter,
                    sampleRate: configuration.clapSampleRate,
                    preRollSeconds: configuration.clapPreRollSeconds
                )
                let videoWindow = AudioAnalysis.gateTransientWindow(rawVideoWindow, noiseFloor: videoNoiseFloor)
                let audioWindow = AudioAnalysis.gateTransientWindow(rawAudioWindow, noiseFloor: audioNoiseFloor)
                let rangesLength = min(videoWindow.count, audioWindow.count)
                guard rangesLength > 32 else { continue }

                let rawScore = AudioAnalysis.normalizedCorrelation(
                    Array(videoWindow.prefix(rangesLength)),
                    Array(audioWindow.prefix(rangesLength))
                )
                let prominence = min(
                    AudioAnalysis.peakProminence(values: videoEnvelope, peakIndex: videoPeak),
                    AudioAnalysis.peakProminence(values: audioEnvelope, peakIndex: audioPeak)
                )
                let videoSNR = AudioAnalysis.signalToNoiseRatioDB(signalRMS: AudioAnalysis.rms(rawVideoWindow), noiseFloor: videoNoiseFloor)
                let audioSNR = AudioAnalysis.signalToNoiseRatioDB(signalRMS: AudioAnalysis.rms(rawAudioWindow), noiseFloor: audioNoiseFloor)
                let snr = min(videoSNR, audioSNR)
                let compositeScore = (rawScore * 0.85) + (prominence * 0.10) + (max(0, min(1, snr / 24)) * 0.05)

                if compositeScore > bestCompositeScore {
                    let offsetSeconds = Double(audioCenter - videoCenter) / configuration.clapSampleRate
                    bestCompositeScore = compositeScore
                    bestSNR = snr
                    bestOffsetFrames = Int((offsetSeconds * fps).rounded())
                    bestClapTime = Double(videoCenter) / configuration.clapSampleRate
                }
            }
        }

        guard bestCompositeScore >= configuration.mediumConfidenceThreshold else { return nil }
        let confidence = calibratedClapConfidence(score: bestCompositeScore, snrDB: bestSNR)
        return SyncResult(
            confidence: confidence,
            method: .waveformCorrelation,
            offsetFrames: bestOffsetFrames,
            clapDetectedAt: bestClapTime
        )
    }

    private func fullFileCorrelation(videoURL: URL, audioURL: URL, fps: Double) async throws -> SyncResult {
        let video = try await AudioFileLoader.loadMonoSamples(from: videoURL)
        let audio = try await AudioFileLoader.loadMonoSamples(from: audioURL)
        let videoSamples = video.samples.map { abs($0) }
        let audioSamples = audio.samples.map { abs($0) }

        let coarseReference = AudioAnalysis.downsample(videoSamples, from: video.sampleRate, to: configuration.coarseCorrelationRate)
        let coarseComparison = AudioAnalysis.downsample(audioSamples, from: audio.sampleRate, to: configuration.coarseCorrelationRate)
        let coarseMaxLag = Int(configuration.searchWindowSeconds * configuration.coarseCorrelationRate)
        let coarse = AudioAnalysis.bestLag(reference: coarseReference, comparison: coarseComparison, maxLag: coarseMaxLag)

        let fineReference = AudioAnalysis.downsample(videoSamples, from: video.sampleRate, to: configuration.fineCorrelationRate)
        let fineComparison = AudioAnalysis.downsample(audioSamples, from: audio.sampleRate, to: configuration.fineCorrelationRate)
        let coarseLagInFineSamples = Int((Double(coarse.lag) / configuration.coarseCorrelationRate) * configuration.fineCorrelationRate)
        let fine = AudioAnalysis.refineLag(
            reference: fineReference,
            comparison: fineComparison,
            around: coarseLagInFineSamples,
            radius: Int(configuration.fineCorrelationRate)
        )

        let offsetSeconds = Double(fine.lag) / configuration.fineCorrelationRate
        let offsetFrames = Int((offsetSeconds * fps).rounded())
        let confidence: SyncConfidence

        switch fine.score {
        case let score where score >= 0.70:
            confidence = .medium
        case let score where score >= 0.50:
            confidence = .low
        default:
            confidence = .manualRequired
        }

        return SyncResult(
            confidence: confidence,
            method: .waveformCorrelation,
            offsetFrames: offsetFrames
        )
    }

    private func correctDrift(result: SyncResult, videoURL: URL, audioURL: URL, fps: Double) async throws -> SyncResult {
        let video = try await AudioFileLoader.loadMonoSamples(from: videoURL)
        let audio = try await AudioFileLoader.loadMonoSamples(from: audioURL)
        let duration = min(video.duration, audio.duration)

        guard duration > 300 else { return result }

        let probeSeconds = 30.0
        let sampleRate = configuration.fineCorrelationRate
        let videoFine = AudioAnalysis.downsample(video.samples, from: video.sampleRate, to: sampleRate)
        let audioFine = AudioAnalysis.downsample(audio.samples, from: audio.sampleRate, to: sampleRate)
        let probeLength = Int(probeSeconds * sampleRate)
        let startVideo = Array(videoFine.prefix(probeLength))
        let startAudio = Array(audioFine.prefix(probeLength))
        let endVideo = Array(videoFine.suffix(probeLength))
        let endAudio = Array(audioFine.suffix(probeLength))
        let radius = Int(sampleRate / 2)

        let startLag = AudioAnalysis.refineLag(reference: startVideo, comparison: startAudio, around: 0, radius: radius).lag
        let endLag = AudioAnalysis.refineLag(reference: endVideo, comparison: endAudio, around: 0, radius: radius).lag
        let driftSeconds = Double(endLag - startLag) / sampleRate
        let driftPPM = (driftSeconds / duration) * 1_000_000

        return SyncResult(
            confidence: result.confidence,
            method: result.method,
            offsetFrames: result.offsetFrames,
            driftPPM: driftPPM,
            clapDetectedAt: result.clapDetectedAt,
            verifiedAt: result.verifiedAt
        )
    }

    private func calibratedClapConfidence(score: Float, snrDB: Float) -> SyncConfidence {
        if score >= configuration.highConfidenceThreshold, snrDB >= 0 {
            return .high
        }
        if score >= configuration.mediumConfidenceThreshold {
            return .medium
        }
        return .low
    }
}
