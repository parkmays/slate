import Foundation

private final class SLATEConfigurationBundleToken {}

/// Centralized configuration management for SLATE components
public struct SLATEConfiguration: Codable, Sendable {
    
    // MARK: - Sync Engine Configuration
    
    public struct SyncEngine: Codable, Sendable {
        /// Confidence thresholds for sync results
        public let confidenceThresholds: ConfidenceThresholds
        
        /// Performance optimization settings
        public let performance: PerformanceSettings
        
        /// Audio processing settings
        public let audio: AudioSettings
        
        /// Maximum file sizes for different processing strategies
        public let limits: ProcessingLimits
        
        public init(
            confidenceThresholds: ConfidenceThresholds = .init(),
            performance: PerformanceSettings = .init(),
            audio: AudioSettings = .init(),
            limits: ProcessingLimits = .init()
        ) {
            self.confidenceThresholds = confidenceThresholds
            self.performance = performance
            self.audio = audio
            self.limits = limits
        }
    }
    
    public struct ConfidenceThresholds: Codable, Sendable {
        /// High confidence threshold (0.0-1.0)
        public let high: Double
        
        /// Medium confidence threshold (0.0-1.0)
        public let medium: Double
        
        /// Low confidence threshold (0.0-1.0)
        public let low: Double
        
        /// Maximum allowed drift in PPM for high confidence
        public let maxDriftHighPPM: Double
        
        /// Maximum allowed drift in PPM for medium confidence
        public let maxDriftMediumPPM: Double
        
        /// Maximum allowed offset in frames for high confidence
        public let maxOffsetHighFrames: Int
        
        /// Maximum allowed offset in frames for medium confidence
        public let maxOffsetMediumFrames: Int
        
        public init(
            high: Double = 0.9,
            medium: Double = 0.7,
            low: Double = 0.5,
            maxDriftHighPPM: Double = 5.0,
            maxDriftMediumPPM: Double = 20.0,
            maxOffsetHighFrames: Int = 0,
            maxOffsetMediumFrames: Int = 2
        ) {
            self.high = high
            self.medium = medium
            self.low = low
            self.maxDriftHighPPM = maxDriftHighPPM
            self.maxDriftMediumPPM = maxDriftMediumPPM
            self.maxOffsetHighFrames = maxOffsetHighFrames
            self.maxOffsetMediumFrames = maxOffsetMediumFrames
        }
    }
    
    public struct PerformanceSettings: Codable, Sendable {
        /// Use FFT correlation for files larger than this size (bytes)
        public let fftThresholdBytes: Int
        
        /// Use FFT correlation for search windows larger than this
        public let fftThresholdSamples: Int
        
        /// Maximum concurrent operations
        public let maxConcurrentOperations: Int
        
        /// Memory usage limit for streaming (samples)
        public let streamingMemoryLimit: Int
        
        /// Chunk size for audio streaming (samples)
        public let streamingChunkSize: Int
        
        /// Enable GPU acceleration when available
        public let enableGPUAcceleration: Bool
        
        public init(
            fftThresholdBytes: Int = 2_000_000, // 2MB
            fftThresholdSamples: Int = 100,
            maxConcurrentOperations: Int = 4,
            streamingMemoryLimit: Int = 10_000_000, // 10M samples
            streamingChunkSize: Int = 48_000, // 1 second at 48kHz
            enableGPUAcceleration: Bool = true
        ) {
            self.fftThresholdBytes = fftThresholdBytes
            self.fftThresholdSamples = fftThresholdSamples
            self.maxConcurrentOperations = maxConcurrentOperations
            self.streamingMemoryLimit = streamingMemoryLimit
            self.streamingChunkSize = streamingChunkSize
            self.enableGPUAcceleration = enableGPUAcceleration
        }
    }
    
    public struct AudioSettings: Codable, Sendable {
        /// Default sample rate for processing
        public let defaultSampleRate: Double
        
        /// Target sample rate for correlation
        public let correlationSampleRate: Double
        
        /// Filter length for anti-aliasing
        public let antiAliasFilterLength: Int
        
        /// Cutoff frequency ratio for anti-aliasing (0.0-1.0)
        public let antiAliasCutoffRatio: Float
        
        /// Minimum audio duration (seconds) for processing
        public let minDurationSeconds: Double
        
        /// Maximum audio duration (seconds) for role classification
        public let roleClassificationDuration: Double
        
        public init(
            defaultSampleRate: Double = 48000,
            correlationSampleRate: Double = 8000,
            antiAliasFilterLength: Int = 64,
            antiAliasCutoffRatio: Float = 0.9,
            minDurationSeconds: Double = 1.0,
            roleClassificationDuration: Double = 30.0
        ) {
            self.defaultSampleRate = defaultSampleRate
            self.correlationSampleRate = correlationSampleRate
            self.antiAliasFilterLength = antiAliasFilterLength
            self.antiAliasCutoffRatio = antiAliasCutoffRatio
            self.minDurationSeconds = minDurationSeconds
            self.roleClassificationDuration = roleClassificationDuration
        }
    }
    
    public struct ProcessingLimits: Codable, Sendable {
        /// Maximum file size for in-memory processing (bytes)
        public let maxInMemoryFileSize: Int
        
        /// Maximum duration to process in seconds (0 = unlimited)
        public let maxDurationSeconds: Double
        
        /// Timeout for sync operations (seconds)
        public let syncTimeoutSeconds: Double
        
        /// Timeout for AI operations (seconds)
        public let aiTimeoutSeconds: Double
        
        public init(
            maxInMemoryFileSize: Int = 100_000_000, // 100MB
            maxDurationSeconds: Double = 3600, // 1 hour
            syncTimeoutSeconds: Double = 120, // 2 minutes
            aiTimeoutSeconds: Double = 300 // 5 minutes
        ) {
            self.maxInMemoryFileSize = maxInMemoryFileSize
            self.maxDurationSeconds = maxDurationSeconds
            self.syncTimeoutSeconds = syncTimeoutSeconds
            self.aiTimeoutSeconds = aiTimeoutSeconds
        }
    }
    
    // MARK: - AI Pipeline Configuration
    
    public struct AIPipeline: Codable, Sendable {
        /// Vision scoring configuration
        public let vision: VisionSettings
        
        /// Audio scoring configuration
        public let audio: AudioScoringSettings
        
        /// Transcription configuration
        public let transcription: TranscriptionSettings
        
        /// Performance scoring configuration
        public let performance: PerformanceScoringSettings
        
        /// Model management settings
        public let models: ModelSettings
        
        public init(
            vision: VisionSettings = .init(),
            audio: AudioScoringSettings = .init(),
            transcription: TranscriptionSettings = .init(),
            performance: PerformanceScoringSettings = .init(),
            models: ModelSettings = .init()
        ) {
            self.vision = vision
            self.audio = audio
            self.transcription = transcription
            self.performance = performance
            self.models = models
        }
    }
    
    public struct VisionSettings: Codable, Sendable {
        /// Sample rate for frame analysis (frames per second)
        public let sampleFPS: Double
        
        /// Use CoreML models when available
        public let useCoreML: Bool
        
        /// Use optimized processing
        public let useOptimized: Bool
        
        /// Adaptive sampling threshold (duration in seconds)
        public let adaptiveSamplingThreshold: Double
        
        /// Metal compute shader settings
        public let metal: MetalSettings
        
        public init(
            sampleFPS: Double = 2,
            useCoreML: Bool = true,
            useOptimized: Bool = true,
            adaptiveSamplingThreshold: Double = 300, // 5 minutes
            metal: MetalSettings = .init()
        ) {
            self.sampleFPS = sampleFPS
            self.useCoreML = useCoreML
            self.useOptimized = useOptimized
            self.adaptiveSamplingThreshold = adaptiveSamplingThreshold
            self.metal = metal
        }
    }
    
    public struct MetalSettings: Codable, Sendable {
        /// Enable Metal GPU acceleration
        public let enabled: Bool
        
        /// Maximum threads per threadgroup
        public let maxThreadsPerGroup: Int
        
        /// Threadgroup memory size (bytes)
        public let threadgroupMemorySize: Int
        
        public init(
            enabled: Bool = true,
            maxThreadsPerGroup: Int = 256,
            threadgroupMemorySize: Int = 16384
        ) {
            self.enabled = enabled
            self.maxThreadsPerGroup = maxThreadsPerGroup
            self.threadgroupMemorySize = threadgroupMemorySize
        }
    }
    
    public struct AudioScoringSettings: Codable, Sendable {
        /// RMS threshold for detecting silence
        public let silenceThreshold: Float
        
        /// Clipping threshold (0.0-1.0)
        public let clippingThreshold: Float
        
        /// Noise floor threshold
        public let noiseFloorThreshold: Float
        
        public init(
            silenceThreshold: Float = 0.01,
            clippingThreshold: Float = 0.95,
            noiseFloorThreshold: Float = 0.001
        ) {
            self.silenceThreshold = silenceThreshold
            self.clippingThreshold = clippingThreshold
            self.noiseFloorThreshold = noiseFloorThreshold
        }
    }
    
    public struct TranscriptionSettings: Codable, Sendable {
        /// Whisper model variant
        public let model: WhisperModel
        
        /// Language code (empty = auto-detect)
        public let language: String
        
        /// Enable timestamps
        public let enableTimestamps: Bool
        
        /// Minimum confidence for word-level timestamps
        public let minWordConfidence: Float
        
        public init(
            model: WhisperModel = .base,
            language: String = "",
            enableTimestamps: Bool = true,
            minWordConfidence: Float = 0.5
        ) {
            self.model = model
            self.language = language
            self.enableTimestamps = enableTimestamps
            self.minWordConfidence = minWordConfidence
        }
    }
    
    public enum WhisperModel: String, Codable, CaseIterable, Sendable {
        case tiny = "tiny"
        case base = "base"
        case small = "small"
        case medium = "medium"
        case large = "large"
        
        public var size: Int {
            switch self {
            case .tiny: return 39
            case .base: return 74
            case .small: return 244
            case .medium: return 769
            case .large: return 1550
            }
        }
    }
    
    public struct PerformanceScoringSettings: Codable, Sendable {
        /// Weight for content density in composite score
        public let contentDensityWeight: Double
        
        /// Weight for performance metrics in composite score
        public let performanceWeight: Double
        
        public init(
            contentDensityWeight: Double = 0.5,
            performanceWeight: Double = 0.5
        ) {
            self.contentDensityWeight = contentDensityWeight
            self.performanceWeight = performanceWeight
        }
    }
    
    public struct ModelSettings: Codable, Sendable {
        /// Graceful degradation settings
        public let degradation: DegradationSettings
        
        /// Confidence tracking settings
        public let confidenceTracking: ConfidenceTrackingSettings
        
        /// Caching settings
        public let caching: CachingSettings
        
        public init(
            degradation: DegradationSettings = .init(),
            confidenceTracking: ConfidenceTrackingSettings = .init(),
            caching: CachingSettings = .init()
        ) {
            self.degradation = degradation
            self.confidenceTracking = confidenceTracking
            self.caching = caching
        }
    }
    
    public struct DegradationSettings: Codable, Sendable {
        /// Maximum consecutive failures before cooldown
        public let maxConsecutiveFailures: Int
        
        /// Cooldown period after failures (seconds)
        public let cooldownPeriod: TimeInterval
        
        /// Performance threshold for triggering degradation (seconds)
        public let performanceThreshold: TimeInterval
        
        /// Confidence threshold for triggering degradation
        public let confidenceThreshold: Double
        
        public init(
            maxConsecutiveFailures: Int = 3,
            cooldownPeriod: TimeInterval = 300, // 5 minutes
            performanceThreshold: TimeInterval = 60.0,
            confidenceThreshold: Double = 0.3
        ) {
            self.maxConsecutiveFailures = maxConsecutiveFailures
            self.cooldownPeriod = cooldownPeriod
            self.performanceThreshold = performanceThreshold
            self.confidenceThreshold = confidenceThreshold
        }
    }
    
    public struct ConfidenceTrackingSettings: Codable, Sendable {
        /// Maximum number of inference results to keep in history
        public let maxHistorySize: Int
        
        /// Enable trend analysis
        public let enableTrendAnalysis: Bool
        
        /// Window size for trend analysis
        public let trendWindowSize: Int
        
        public init(
            maxHistorySize: Int = 1000,
            enableTrendAnalysis: Bool = true,
            trendWindowSize: Int = 10
        ) {
            self.maxHistorySize = maxHistorySize
            self.enableTrendAnalysis = enableTrendAnalysis
            self.trendWindowSize = trendWindowSize
        }
    }
    
    public struct CachingSettings: Codable, Sendable {
        /// Enable result caching
        public let enabled: Bool
        
        /// Maximum cache size (number of entries)
        public let maxSize: Int
        
        /// TTL for cache entries (seconds)
        public let ttl: TimeInterval
        
        /// Cache key includes file checksum
        public let includeChecksum: Bool
        
        public init(
            enabled: Bool = true,
            maxSize: Int = 1000,
            ttl: TimeInterval = 3600, // 1 hour
            includeChecksum: Bool = true
        ) {
            self.enabled = enabled
            self.maxSize = maxSize
            self.ttl = ttl
            self.includeChecksum = includeChecksum
        }
    }
    
    // MARK: - Logging Configuration
    
    public struct Logging: Codable, Sendable {
        /// Log level
        public let level: LogLevel
        
        /// Enable structured logging
        public let structured: Bool
        
        /// Log file path (empty = console only)
        public let filePath: String
        
        /// Maximum log file size (bytes)
        public let maxFileSize: Int
        
        /// Number of log files to keep
        public let maxFiles: Int
        
        /// Enable performance metrics logging
        public let enableMetrics: Bool
        
        public init(
            level: LogLevel = .info,
            structured: Bool = true,
            filePath: String = "",
            maxFileSize: Int = 10_000_000, // 10MB
            maxFiles: Int = 5,
            enableMetrics: Bool = true
        ) {
            self.level = level
            self.structured = structured
            self.filePath = filePath
            self.maxFileSize = maxFileSize
            self.maxFiles = maxFiles
            self.enableMetrics = enableMetrics
        }
        
        public static let `default` = SLATEConfiguration.Logging()
    }
    
    public enum LogLevel: String, Codable, CaseIterable, Sendable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
    }
    
    // MARK: - Properties
    
    public let syncEngine: SyncEngine
    public let aiPipeline: AIPipeline
    public let logging: Logging
    
    public init(
        syncEngine: SyncEngine = .init(),
        aiPipeline: AIPipeline = .init(),
        logging: Logging = .init()
    ) {
        self.syncEngine = syncEngine
        self.aiPipeline = aiPipeline
        self.logging = logging
    }
    
    // MARK: - Configuration Loading
    
    /// Load configuration from file
    public static func load(from url: URL) throws -> SLATEConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SLATEConfiguration.self, from: data)
    }
    
    /// Save configuration to file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
    
    /// Load configuration from bundle
    public static func loadFromBundle(name: String = "slate-config") throws -> SLATEConfiguration {
        let bundle = Bundle(for: SLATEConfigurationBundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ConfigurationError.fileNotFound(name)
        }
        return try load(from: url)
    }
    
    /// Get default configuration
    public static let `default` = SLATEConfiguration()
}

// MARK: - Errors

public enum ConfigurationError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidFormat(Error)
    case missingRequired(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let name):
            return "Configuration file not found: \(name)"
        case .invalidFormat(let error):
            return "Invalid configuration format: \(error.localizedDescription)"
        case .missingRequired(let key):
            return "Missing required configuration key: \(key)"
        }
    }
}

// MARK: - Configuration Manager

/// Global configuration manager
public actor ConfigurationManager {
    
    nonisolated(unsafe) private static var sharedInstance: ConfigurationManager?
    
    private var configuration: SLATEConfiguration
    
    private init(configuration: SLATEConfiguration) {
        self.configuration = configuration
    }
    
    /// Get shared configuration manager
    public static func shared() -> ConfigurationManager {
        if let existing = sharedInstance {
            return existing
        }
        let config = SLATEConfiguration.default
        let manager = ConfigurationManager(configuration: config)
        sharedInstance = manager
        return manager
    }
    
    /// Load configuration from file
    public static func load(from url: URL) throws -> ConfigurationManager {
        let configuration = try SLATEConfiguration.load(from: url)
        let manager = ConfigurationManager(configuration: configuration)
        sharedInstance = manager
        return manager
    }
    
    /// Get current configuration
    public var current: SLATEConfiguration {
        return configuration
    }
    
    /// Update configuration
    public func update(_ newConfiguration: SLATEConfiguration) {
        configuration = newConfiguration
    }
    
    /// Update specific configuration section
    public func updateSyncEngine(_ syncConfig: SLATEConfiguration.SyncEngine) {
        configuration = SLATEConfiguration(
            syncEngine: syncConfig,
            aiPipeline: configuration.aiPipeline,
            logging: configuration.logging
        )
    }
    
    public func updateAIPipeline(_ aiConfig: SLATEConfiguration.AIPipeline) {
        configuration = SLATEConfiguration(
            syncEngine: configuration.syncEngine,
            aiPipeline: aiConfig,
            logging: configuration.logging
        )
    }
}

// MARK: - Convenience Extensions

extension SLATEConfiguration.SyncEngine {
    /// Determine if should use FFT correlation
    public func shouldUseFFT(fileSize: Int, searchWindow: Int) -> Bool {
        return fileSize > performance.fftThresholdBytes || 
               searchWindow > performance.fftThresholdSamples
    }
    
    /// Check if should use streaming for file size
    public func shouldUseStreaming(fileSize: Int) -> Bool {
        return fileSize > limits.maxInMemoryFileSize
    }
}

extension SLATEConfiguration.VisionSettings {
    /// Determine sample rate based on duration
    public func sampleRate(for duration: Double) -> Double {
        if duration > adaptiveSamplingThreshold {
            return max(1, sampleFPS / 2) // Sample less frequently for long videos
        }
        return sampleFPS
    }
}
