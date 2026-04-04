import Foundation
import SLATESharedTypes

/// Consistent API wrapper for SyncEngine operations
public struct SyncEngineAPI {
    
    public enum SyncError: Error, LocalizedError {
        case invalidInput(String)
        case processingFailed(Error)
        case timeout
        case insufficientData
        
        public var errorDescription: String? {
            switch self {
            case .invalidInput(let message):
                return "Invalid input: \(message)"
            case .processingFailed(let error):
                return "Processing failed: \(error.localizedDescription)"
            case .timeout:
                return "Operation timed out"
            case .insufficientData:
                return "Insufficient data for processing"
            }
        }
    }
    
    private let engine: SyncEngine
    private let logger: SLATELogger
    private let configuration: SLATEConfiguration.SyncEngine
    
    public init(
        engine: SyncEngine = SyncEngine(),
        configuration: SLATEConfiguration.SyncEngine = .init()
    ) {
        self.engine = engine
        self.configuration = configuration
        self.logger = SLATELogger(category: "SyncEngineAPI")
    }
    
    // MARK: - Consistent Sync Methods
    
    /// Synchronize two audio clips with consistent error handling
    public func syncClips(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> MultiCamSyncResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        logger.info("Starting sync operation", metadata: [
            "primary": primary.lastPathComponent,
            "secondary": secondary.lastPathComponent,
            "fps": fps
        ])
        
        do {
            // Validate inputs
            try validateInputs(primary: primary, secondary: secondary, fps: fps)
            
            // Check file sizes to determine processing strategy
            let primarySize = try FileManager.default.attributesOfItem(atPath: primary.path)[.size] as? Int ?? 0
            let secondarySize = try FileManager.default.attributesOfItem(atPath: secondary.path)[.size] as? Int ?? 0
            
            // Use streaming if files are too large
            if configuration.shouldUseStreaming(fileSize: max(primarySize, secondarySize)) {
                logger.info("Using streaming processing for large files")
                return try await syncWithStreaming(primary: primary, secondary: secondary, fps: fps)
            }
            
            // Standard processing
            let result = try await engine.syncClip(
                primary: primary,
                secondary: secondary,
                fps: fps
            )
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            logger.info("Sync completed successfully", metadata: [
                "offsetFrames": result.offsetFrames,
                "confidence": result.confidence.rawValue,
                "method": result.method.rawValue,
                "duration": duration
            ])
            
            // Record metrics
            await MetricsManager.shared.recordPerformance(
                operation: "sync",
                duration: duration,
                metadata: [
                    "method": result.method.rawValue,
                    "confidence": result.confidence.rawValue,
                    "fileSize": max(primarySize, secondarySize)
                ]
            )
            
            return result
            
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            logger.error("Sync failed", metadata: [
                "duration": duration,
                "error": error.localizedDescription
            ], error: error)
            
            // Convert to consistent error type
            throw SyncError.processingFailed(error)
        }
    }
    
    /// Assign audio roles with consistent error handling
    public func assignAudioRoles(tracks: [URL]) async throws -> [AudioTrack] {
        logger.info("Assigning audio roles", metadata: [
            "trackCount": tracks.count
        ])
        
        do {
            // Validate inputs
            guard !tracks.isEmpty else {
                throw SyncError.invalidInput("No audio tracks provided")
            }
            
            // Check all files exist
            for track in tracks {
                guard FileManager.default.fileExists(atPath: track.path) else {
                    throw SyncError.invalidInput("Audio file not found: \(track.lastPathComponent)")
                }
            }
            
            let result = await engine.assignAudioRoles(tracks: tracks)
            
            logger.info("Audio roles assigned", metadata: [
                "assignedRoles": result.map { $0.role.rawValue }
            ])
            
            return result
            
        } catch {
            logger.error("Failed to assign audio roles", error: error)
            throw SyncError.processingFailed(error)
        }
    }
    
    /// Get performance metrics with consistent format
    public func getPerformanceMetrics() -> SyncPerformanceMetrics? {
        // This would be implemented in the actual SyncEngine
        return nil
    }
    
    // MARK: - Private Methods
    
    private func validateInputs(primary: URL, secondary: URL, fps: Double) throws {
        // Check file existence
        guard FileManager.default.fileExists(atPath: primary.path) else {
            throw SyncError.invalidInput("Primary audio file not found")
        }
        
        guard FileManager.default.fileExists(atPath: secondary.path) else {
            throw SyncError.invalidInput("Secondary audio file not found")
        }
        
        // Validate FPS
        guard fps > 0 && fps <= 120 else {
            throw SyncError.invalidInput("Invalid FPS value: \(fps)")
        }
        
        // Check minimum duration
        let primaryDuration = try getAudioDuration(primary)
        let secondaryDuration = try getAudioDuration(secondary)
        
        let minDuration = configuration.audio.minDurationSeconds
        guard primaryDuration >= minDuration && secondaryDuration >= minDuration else {
            throw SyncError.insufficientData
        }
    }
    
    private func getAudioDuration(_ url: URL) throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        return try asset.load(.duration).seconds
    }
    
    private func syncWithStreaming(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> MultiCamSyncResult {
        // Use streaming processor for large files
        let processor = StreamingAudioProcessor(
            maxMemoryUsage: configuration.performance.streamingMemoryLimit
        )
        
        logger.info("Performing streaming correlation")
        
        let result = try await processor.correlateStreaming(
            primaryURL: primary,
            secondaryURL: secondary,
            maxLag: Int(30 * fps) // 30 second max offset
        )
        
        // Convert to MultiCamSyncResult
        let confidence = determineConfidence(score: result.score)
        
        return MultiCamSyncResult(
            cameraURL: secondary,
            offsetFrames: result.lag,
            offsetSeconds: Double(result.lag) / fps,
            confidence: confidence,
            method: .audioCorrelation
        )
    }
    
    private func determineConfidence(score: Float) -> SyncConfidence {
        switch score {
        case 0.9...1.0:
            return .high
        case 0.7..<0.9:
            return .medium
        case 0.5..<0.7:
            return .low
        default:
            return .manualRequired
        }
    }
}

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
            // Validate clip
            try validateClip(clip)
            
            // Check if we have cached results
            if let cachedResult = await getCachedResult(for: clip) {
                logger.info("Using cached AI results")
                return cachedResult
            }
            
            // Perform analysis
            let result = try await pipeline.analyzeClip(clip)
            
            // Cache the result
            await cacheResult(result, for: clip)
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            
            logger.info("AI analysis completed", metadata: [
                "compositeScore": result.aiScores.composite,
                "duration": duration,
                "hasTranscript": result.transcript != nil
            ])
            
            // Record metrics
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
        return pipeline.getPerformanceReport()
    }
    
    /// Get degradation status
    public func getDegradationStatus() -> HealthReport {
        return pipeline.getDegradationStatus()
    }
    
    // MARK: - Private Methods
    
    private func validateClip(_ clip: Clip) throws {
        // Check basic requirements
        guard clip.duration > 0 else {
            throw PipelineError.invalidClip("Invalid duration")
        }
        
        // For vision scoring, we need a proxy
        if clip.proxyPath == nil {
            logger.warning("No proxy available for vision scoring")
        }
        
        // For audio scoring and transcription, we need synced audio
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
            transcript: nil // Transcript not cached
        )
    }
    
    private func cacheResult(_ result: ClipAnalysisResult, for clip: Clip) async {
        guard let cache = await CacheManager.shared.getAIScoreCache() else { return }
        
        let cached = CachedAIScores(
            scores: result.aiScores,
            modelVersions: [:], // Would extract from actual result
            confidences: [:],
            processingTimes: [:]
        )
        
        await cache.setAIScores(cached, for: clip)
    }
}

// MARK: - Unified API

/// Unified API for consistent access to all SLATE components
public struct SLATEAPI {
    
    private let syncAPI: SyncEngineAPI
    private let aiAPI: AIPipelineAPI
    private let logger: SLATELogger
    
    public init(configuration: SLATEConfiguration = .default) {
        self.syncAPI = SyncEngineAPI(configuration: configuration.syncEngine)
        self.aiAPI = AIPipelineAPI(configuration: configuration.aiPipeline)
        self.logger = SLATELogger(category: "SLATEAPI")
        
        // Initialize subsystems
        Task {
            await initializeSubsystems(configuration: configuration)
        }
    }
    
    /// Process a clip through the full pipeline
    public func processClip(
        primaryAudio: URL,
        secondaryAudio: URL,
        proxyVideo: URL,
        fps: Double
    ) async throws -> ProcessedClipResult {
        logger.info("Starting full pipeline processing")
        
        // Step 1: Sync audio
        let syncResult = try await syncAPI.syncClips(
            primary: primaryAudio,
            secondary: secondaryAudio,
            fps: fps
        )
        
        // Step 2: Assign audio roles
        let audioTracks = try await syncAPI.assignAudioRoles(
            tracks: [primaryAudio, secondaryAudio]
        )
        
        // Step 3: Create clip
        let clip = createClip(
            primaryAudio: primaryAudio,
            secondaryAudio: secondaryAudio,
            proxyVideo: proxyVideo,
            fps: fps,
            syncResult: syncResult,
            audioTracks: audioTracks
        )
        
        // Step 4: AI analysis
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
        audioTracks: [AudioTrack]
    ) -> Clip {
        return Clip(
            id: UUID().uuidString,
            projectId: UUID().uuidString,
            checksum: "temp",
            sourcePath: primaryAudio.path,
            sourceSize: 1000000,
            sourceFormat: .proRes422HQ,
            sourceFps: fps,
            sourceTimecodeStart: "01:00:00:00",
            duration: 30, // Would extract from actual file
            proxyPath: proxyVideo.path,
            proxyStatus: .ready,
            proxyChecksum: nil,
            proxyLUT: nil,
            proxyColorSpace: nil,
            narrativeMeta: nil,
            documentaryMeta: nil,
            audioTracks: audioTracks,
            syncResult: SyncResult(
                confidence: syncResult.confidence,
                method: syncResult.method,
                offsetFrames: syncResult.offsetFrames
            ),
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

public struct SyncPerformanceMetrics {
    public let samplesProcessedPerSecond: Double
    public let totalProcessingTime: TimeInterval
    public let methodBreakdown: [String: TimeInterval]
}
