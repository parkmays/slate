import Foundation
import CoreML
import SLATESharedTypes

/// Manages graceful degradation when AI models fail to load or perform poorly
public struct GracefulDegradationManager {
    
    public enum DegradationLevel: Int, CaseIterable {
        case full = 0      // All models working
        case reduced = 1   // Some models failed, using fallbacks
        case minimal = 2   // Only basic heuristics available
        case offline = 3   // No AI processing possible
        
        public var description: String {
            switch self {
            case .full: return "Full AI capabilities available"
            case .reduced: return "Reduced AI capabilities with fallbacks"
            case .minimal: return "Minimal processing with basic heuristics"
            case .offline: return "AI processing unavailable"
            }
        }
    }
    
    public enum ModelFailure {
        case notFound(String)
        case compilationFailed(String, Error)
        case loadFailed(String, Error)
        case inferenceFailed(String, Error)
        case performanceTooSlow(String, TimeInterval)
        case confidenceTooLow(String, Double)
        
        public var model: String {
            switch self {
            case .notFound(let model), .compilationFailed(let model, _),
                 .loadFailed(let model, _), .inferenceFailed(let model, _),
                 .performanceTooSlow(let model, _), .confidenceTooLow(let model, _):
                return model
            }
        }
    }
    
    private var currentLevel: DegradationLevel = .full
    private var failedModels: Set<String> = []
    private var modelHealth: [String: ModelHealthStatus] = [:]
    private let configuration: DegradationConfiguration
    
    public init(configuration: DegradationConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Model Health Management
    
    public mutating func reportModelFailure(_ failure: ModelFailure) {
        failedModels.insert(failure.model)
        
        // Update health status
        let status = ModelHealthStatus(
            isHealthy: false,
            lastFailure: failure,
            consecutiveFailures: (modelHealth[failure.model]?.consecutiveFailures ?? 0) + 1,
            lastCheck: Date()
        )
        modelHealth[failure.model] = status
        
        // Determine degradation level
        updateDegradationLevel()
        
        // Log the failure
        print("⚠️ Model failure reported: \(failure.model) - \(failure)")
        print("📊 Current degradation level: \(currentLevel.description)")
    }
    
    public mutating func reportModelSuccess(_ model: String, confidence: Double? = nil, processingTime: TimeInterval? = nil) {
        failedModels.remove(model)
        
        // Update health status
        let status = ModelHealthStatus(
            isHealthy: true,
            lastFailure: nil,
            consecutiveFailures: 0,
            lastCheck: Date(),
            lastConfidence: confidence,
            lastProcessingTime: processingTime
        )
        modelHealth[model] = status
        
        // Check if we can improve degradation level
        updateDegradationLevel()
        
        // Log recovery
        if modelHealth[model]?.consecutiveFailures ?? 0 > 0 {
            print("✅ Model recovered: \(model)")
            print("📊 Current degradation level: \(currentLevel.description)")
        }
    }
    
    private mutating func updateDegradationLevel() {
        let criticalModels = ["vision-coreml", "audio-coreml", "performance-coreml"]
        let failedCritical = criticalModels.filter { failedModels.contains($0) }
        
        if failedModels.isEmpty {
            currentLevel = .full
        } else if failedCritical.count <= 1 {
            currentLevel = .reduced
        } else if failedCritical.count <= 2 {
            currentLevel = .minimal
        } else {
            currentLevel = .offline
        }
    }
    
    // MARK: - Degradation Strategies
    
    public func shouldUseModel(_ model: String) -> Bool {
        guard let health = modelHealth[model] else { return true }
        
        // If model is healthy, use it
        if health.isHealthy {
            return true
        }
        
        // If model has failed too many times, don't use it
        if health.consecutiveFailures >= configuration.maxConsecutiveFailures {
            return false
        }
        
        // If last failure was recent, don't use it
        if let lastFailure = health.lastFailure,
           Date().timeIntervalSince(lastFailure as Date) < configuration.cooldownPeriod {
            return false
        }
        
        return true
    }
    
    public func getFallbackStrategy(for model: String) -> FallbackStrategy {
        switch model {
        case "vision-coreml":
            return currentLevel == .minimal ? .basicHeuristics : .optimizedHeuristics
        case "audio-coreml":
            return .basicHeuristics
        case "performance-coreml":
            return .ruleBasedScoring
        case "transcription-whisper":
            return .noTranscription
        default:
            return .basicHeuristics
        }
    }
    
    public func shouldRetryModel(_ model: String) -> Bool {
        guard let health = modelHealth[model] else { return true }
        
        // Retry if cooldown period has passed
        if let lastFailure = health.lastFailure,
           Date().timeIntervalSince(lastFailure as Date) >= configuration.cooldownPeriod {
            return true
        }
        
        return false
    }
    
    // MARK: - Monitoring
    
    public func getHealthReport() -> HealthReport {
        return HealthReport(
            currentLevel: currentLevel,
            failedModels: Array(failedModels),
            modelHealth: modelHealth,
            generatedAt: Date()
        )
    }
    
    public func getModelStatus(_ model: String) -> ModelHealthStatus? {
        return modelHealth[model]
    }
    
    public func getCurrentLevel() -> DegradationLevel {
        return currentLevel
    }
}

// MARK: - Configuration

public struct DegradationConfiguration {
    public let maxConsecutiveFailures: Int
    public let cooldownPeriod: TimeInterval
    public let performanceThreshold: TimeInterval
    public let confidenceThreshold: Double
    
    public static let `default` = DegradationConfiguration(
        maxConsecutiveFailures: 3,
        cooldownPeriod: 300, // 5 minutes
        performanceThreshold: 60.0, // seconds
        confidenceThreshold: 0.3
    )
    
    public init(maxConsecutiveFailures: Int, cooldownPeriod: TimeInterval, 
                performanceThreshold: TimeInterval, confidenceThreshold: Double) {
        self.maxConsecutiveFailures = maxConsecutiveFailures
        self.cooldownPeriod = cooldownPeriod
        self.performanceThreshold = performanceThreshold
        self.confidenceThreshold = confidenceThreshold
    }
}

// MARK: - Supporting Types

public struct ModelHealthStatus {
    public let isHealthy: Bool
    public let lastFailure: GracefulDegradationManager.ModelFailure?
    public let consecutiveFailures: Int
    public let lastCheck: Date
    public let lastConfidence: Double?
    public let lastProcessingTime: TimeInterval?
    
    public init(isHealthy: Bool, lastFailure: GracefulDegradationManager.ModelFailure?, 
                consecutiveFailures: Int, lastCheck: Date, 
                lastConfidence: Double? = nil, lastProcessingTime: TimeInterval? = nil) {
        self.isHealthy = isHealthy
        self.lastFailure = lastFailure
        self.consecutiveFailures = consecutiveFailures
        self.lastCheck = lastCheck
        self.lastConfidence = lastConfidence
        self.lastProcessingTime = lastProcessingTime
    }
}

public enum FallbackStrategy {
    case optimizedHeuristics  // Use optimized algorithmic fallbacks
    case basicHeuristics      // Use simple heuristics
    case ruleBasedScoring     // Use rule-based scoring
    case noTranscription      // Skip transcription
    case cachedResults        // Use cached results if available
    case manualIntervention   // Require manual review
}

public struct HealthReport {
    public let currentLevel: GracefulDegradationManager.DegradationLevel
    public let failedModels: [String]
    public let modelHealth: [String: ModelHealthStatus]
    public let generatedAt: Date
    
    public func generateSummary() -> String {
        var summary = "AI Model Health Report\n"
        summary += "======================\n\n"
        summary += "Status: \(currentLevel.description)\n"
        summary += "Failed Models: \(failedModels.count)\n\n"
        
        if !failedModels.isEmpty {
            summary += "Failed Models:\n"
            for model in failedModels.sorted() {
                if let health = modelHealth[model] {
                    summary += "  • \(model): \(health.lastFailure?.model ?? "Unknown")\n"
                }
            }
            summary += "\n"
        }
        
        let healthyModels = modelHealth.filter { $0.value.isHealthy }.keys.sorted()
        if !healthyModels.isEmpty {
            summary += "Healthy Models:\n"
            for model in healthyModels {
                summary += "  • \(model)\n"
            }
        }
        
        return summary
    }
}

// MARK: - Extension for CoreMLModelManager

extension CoreMLModelManager {
    private static var degradationManager = GracefulDegradationManager()
    
    public func loadModelsWithGracefulDegradation() async throws {
        let models: [ModelType] = [.visionQuality, .audioQuality, .performance]
        
        for modelType in models {
            do {
                _ = try await loadModel(modelType)
                CoreMLModelManager.degradationManager.reportModelSuccess(modelType.filename)
            } catch {
                let failure: GracefulDegradationManager.ModelFailure
                
                if error.localizedDescription.contains("not found") {
                    failure = .notFound(modelType.filename)
                } else if error.localizedDescription.contains("compile") {
                    failure = .compilationFailed(modelType.filename, error)
                } else {
                    failure = .loadFailed(modelType.filename, error)
                }
                
                CoreMLModelManager.degradationManager.reportModelFailure(failure)
            }
        }
    }
    
    public func scoreWithGracefulDegradation<T>(
        model: ModelType,
        input: T,
        fallback: () throws -> T
    ) async throws -> T {
        // Check if model should be used
        if !CoreMLModelManager.degradationManager.shouldUseModel(model.filename) {
            print("🔄 Using fallback for \(model.filename)")
            return try fallback()
        }
        
        // Try to use the model
        do {
            let startTime = CFAbsoluteTimeGetCurrent()
            let result = try await performInference(model: model, input: input)
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            
            // Check performance
            if processingTime > 60.0 { // 60 second threshold
                CoreMLModelManager.degradationManager.reportModelFailure(
                    .performanceTooSlow(model.filename, processingTime)
                )
                return try fallback()
            }
            
            CoreMLModelManager.degradationManager.reportModelSuccess(
                model.filename,
                processingTime: processingTime
            )
            
            return result
        } catch {
            CoreMLModelManager.degradationManager.reportModelFailure(
                .inferenceFailed(model.filename, error)
            )
            return try fallback()
        }
    }
    
    private func performInference<T>(model: ModelType, input: T) async throws -> T {
        // This would be the actual inference implementation
        // Placeholder for now
        throw NSError(domain: "NotImplemented", code: -1)
    }
}

// MARK: - Global Access

extension AIPipeline {
    public func getDegradationStatus() -> HealthReport {
        return CoreMLModelManager.degradationManager.getHealthReport()
    }
    
    public func forceModelRetry(_ model: String) {
        if CoreMLModelManager.degradationManager.shouldRetryModel(model) {
            print("🔄 Attempting to retry model: \(model)")
            // Trigger model reload
        }
    }
}
