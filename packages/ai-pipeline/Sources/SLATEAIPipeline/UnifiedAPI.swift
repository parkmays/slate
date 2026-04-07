import Foundation
import SLATESharedTypes
import SLATESyncEngine

// MARK: - AI Pipeline API Wrapper

/// Consistent API wrapper for AI Pipeline operations
public struct AIPipelineAPI {

    public enum PipelineError: Error, LocalizedError {
        case invalidClip(String)
        case processingFailed(Error)
        case modelUnavailable(String)
        case timeout

        public var errorDescription: String? {
            switch self {
            case .invalidClip(let message):
                return "Invalid clip: \(message)"
            case .processingFailed(let error):
                return "Processing failed: \(error.localizedDescription)"
            case .modelUnavailable(let model):
                return "Model unavailable: \(model)"
            case .timeout:
                return "Processing timed out"
            }
        }
    }

    private let pipeline: AIPipeline
    private let logger: SLATELogger
    private let configuration: SLATEConfiguration.AIPipeline

    public init(
        pipeline: AIPipeline = AIPipeline(),
        configuration: SLATEConfiguration.AIPipeline = .init()
    ) {
        self.pipeline = pipeline
        self.configuration = configuration
        self.logger = SLATELogger(category: "AIPipelineAPI")
    }

    /// Analyze clip with consistent error handling
    public func analyzeClip(_ clip: Clip) async throws -> ClipAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.info("Starting AI analysis", metadata: [
            "clipId": clip.id,
            "duration": clip.duration,
            "hasProxy": clip.proxyPath != nil
        ])

        do {
            try validateClip(clip)

            if let cachedResult = await getCachedResult(for: clip) {
                logger.info("Using cached AI results")
                return cachedResult
            }

            let result = try await pipeline.analyzeClip(clip)

            await cacheResult(result, for: clip)

            let duration = CFAbsoluteTimeGetCurrent() - startTime

            logger.info("AI analysis completed", metadata: [
                "compositeScore": result.aiScores.composite,
                "duration": duration,
                "hasTranscript": result.transcript != nil
            ])

            await MetricsManager.shared.recordPerformance(
                operation: "ai_analysis",
                duration: duration,
                metadata: [
                    "clipDuration": clip.duration,
                    "compositeScore": result.aiScores.composite
                ]
            )

            return result

        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            logger.error("AI analysis failed", metadata: [
                "duration": duration,
                "error": error.localizedDescription
            ], error: error)

            throw PipelineError.processingFailed(error)
        }
    }

    /// Get performance report
    public func getPerformanceReport() -> PerformanceReport {
        pipeline.getPerformanceReport()
    }

    /// Get degradation status
    public func getDegradationStatus() -> HealthReport {
        pipeline.getDegradationStatus()
    }

    // MARK: - Private Methods

    private func validateClip(_ clip: Clip) throws {
        guard clip.duration > 0 else {
            throw PipelineError.invalidClip("Invalid duration")
        }

        if clip.proxyPath == nil {
            logger.warning("No proxy available for vision scoring")
        }

        if clip.syncedAudioPath == nil {
            logger.warning("No synced audio available for audio analysis")
        }
    }

    private func getCachedResult(for clip: Clip) async -> ClipAnalysisResult? {
        guard let cache = await CacheManager.shared.getAIScoreCache() else { return nil }

        let cached = await cache.getAIScores(for: clip)
        guard let cachedScores = cached else { return nil }

        return ClipAnalysisResult(
            aiScores: cachedScores.scores,
            transcript: nil
        )
    }

    private func cacheResult(_ result: ClipAnalysisResult, for clip: Clip) async {
        guard let cache = await CacheManager.shared.getAIScoreCache() else { return }

        let cached = CachedAIScores(
            scores: result.aiScores,
            modelVersions: [:],
            confidences: [:],
            processingTimes: [:]
        )

        await cache.setAIScores(cached, for: clip)
    }
}

// MARK: - Unified API

/// Unified API for consistent access to all SLATE components
public struct SLATEAPI {

    private let configuration: SLATEConfiguration
    private let syncAPI: SyncEngineAPI
    private let aiAPI: AIPipelineAPI
    private let logger: SLATELogger

    public init(configuration: SLATEConfiguration = .default) {
        self.configuration = configuration
        self.syncAPI = SyncEngineAPI(configuration: configuration.syncEngine)
        self.aiAPI = AIPipelineAPI(configuration: configuration.aiPipeline)
        self.logger = SLATELogger(category: "SLATEAPI")
    }

    /// Prepare caches and pools (call once after creating ``SLATEAPI``).
    public func prepareSubsystems() async {
        await initializeSubsystems(configuration: configuration)
    }

    /// Process a clip through the full pipeline
    public func processClip(
        primaryAudio: URL,
        secondaryAudio: URL,
        proxyVideo: URL,
        fps: Double,
        projectId: String? = nil,
        checksum: String? = nil,
        sourceSize: Int64? = nil,
        duration: Double? = nil,
        timecodeStart: String? = nil
    ) async throws -> ProcessedClipResult {
        logger.info("Starting full pipeline processing")

        let syncResult = try await syncAPI.syncClips(
            primary: primaryAudio,
            secondary: secondaryAudio,
            fps: fps
        )

        let audioTracks = try await syncAPI.assignAudioRoles(
            tracks: [primaryAudio, secondaryAudio]
        )

        let clip = createClip(
            primaryAudio: primaryAudio,
            secondaryAudio: secondaryAudio,
            proxyVideo: proxyVideo,
            fps: fps,
            syncResult: syncResult,
            audioTracks: audioTracks,
            projectId: projectId,
            checksum: checksum,
            sourceSize: sourceSize,
            duration: duration,
            timecodeStart: timecodeStart
        )

        let aiResult = try await aiAPI.analyzeClip(clip)

        return ProcessedClipResult(
            clip: clip,
            syncResult: syncResult,
            audioTracks: audioTracks,
            aiResult: aiResult
        )
    }

    /// Get comprehensive system status
    public func getSystemStatus() async -> SystemStatus {
        await initializeSubsystems(configuration: configuration)
        let metrics = await MetricsManager.shared.generateReport()
        let cacheStats = await CacheManager.shared.getStatistics()
        let poolStats = await PoolManager.shared.getStatistics()

        return SystemStatus(
            metrics: metrics,
            cacheStatistics: cacheStats,
            poolStatistics: poolStats,
            timestamp: Date()
        )
    }

    // MARK: - Private Methods

    private func initializeSubsystems(configuration: SLATEConfiguration) async {
        await CacheManager.shared.initialize(with: configuration)
        await PoolManager.shared.initialize(configuration: configuration)

        logger.info("SLATE subsystems initialized")
    }

    private func createClip(
        primaryAudio: URL,
        secondaryAudio: URL,
        proxyVideo: URL,
        fps: Double,
        syncResult: MultiCamSyncResult,
        audioTracks: [AudioTrack],
        projectId: String?,
        checksum: String?,
        sourceSize: Int64?,
        duration: Double?,
        timecodeStart: String?
    ) -> Clip {
        let offset = syncResult.offsets.first
        let clipSync = SyncResult(
            confidence: offset?.confidence ?? syncResult.overallConfidence,
            method: Self.syncMethod(for: offset?.method),
            offsetFrames: offset?.offsetFrames ?? 0,
            driftPPM: 0
        )

        // Generate a unique ID for this clip
        let clipId = UUID().uuidString
        
        // Use provided project ID or generate a temporary one
        let clipProjectId = projectId ?? UUID().uuidString
        
        // Use provided checksum or generate a placeholder
        let clipChecksum = checksum ?? "pending-\(clipId)"
        
        // Use provided source size or calculate from file
        let clipSourceSize: Int64
        if let size = sourceSize {
            clipSourceSize = size
        } else {
            // Note: This is a synchronous I/O operation. In a production environment,
            // consider moving this to a background queue or making the entire method async
            // to avoid blocking the calling thread.
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: primaryAudio.path)
                clipSourceSize = (attributes[.size] as? Int64) ?? 0
            } catch {
                clipSourceSize = 0
                logger.warning("Could not determine file size", metadata: ["error": error.localizedDescription])
            }
        }
        
        // Use provided duration or estimate from sync result
        let clipDuration = duration ?? 30.0
        
        // Use provided timecode start or default
        let clipTimecodeStart = timecodeStart ?? "01:00:00:00"

        return Clip(
            id: clipId,
            projectId: clipProjectId,
            checksum: clipChecksum,
            sourcePath: primaryAudio.path,
            sourceSize: clipSourceSize,
            sourceFormat: .proRes422HQ,
            sourceFps: fps,
            sourceTimecodeStart: clipTimecodeStart,
            duration: clipDuration,
            proxyPath: proxyVideo.path,
            proxyStatus: .ready,
            proxyChecksum: nil,
            proxyLUT: nil,
            proxyColorSpace: nil,
            narrativeMeta: nil,
            documentaryMeta: nil,
            audioTracks: audioTracks,
            syncResult: clipSync,
            syncedAudioPath: secondaryAudio.path,
            cameraGroupId: nil,
            cameraAngle: nil,
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
            projectMode: .documentary,
            cameraMetadata: nil
        )
    }

    private static func syncMethod(for multiCam: MultiCamSyncMethod?) -> SyncMethod {
        guard let multiCam else { return .manual }
        switch multiCam {
        case .audioCorrelation:
            return .waveformCorrelation
        case .timecodeMetadata:
            return .timecode
        case .slateDetection, .manual:
            return .manual
        }
    }
}

// MARK: - Supporting Types

public struct ProcessedClipResult {
    public let clip: Clip
    public let syncResult: MultiCamSyncResult
    public let audioTracks: [AudioTrack]
    public let aiResult: ClipAnalysisResult
}

public struct SystemStatus {
    public let metrics: MetricsReport
    public let cacheStatistics: CacheStatisticsReport
    public let poolStatistics: PoolStatisticsReport
    public let timestamp: Date
}
