import Foundation
import SLATESharedTypes

/// Tracks confidence metadata for all AI inference results
public struct ConfidenceTracker {
    
    public struct InferenceMetadata {
        public let modelVersion: String
        public let modelType: ModelType
        public let confidence: Double
        public let processingTime: TimeInterval
        public let inputSize: InputSize
        public let timestamp: Date
        public let additionalMetrics: [String: Double]
        
        public init(modelVersion: String, modelType: ModelType, confidence: Double, 
                   processingTime: TimeInterval, inputSize: InputSize, 
                   timestamp: Date = Date(), additionalMetrics: [String: Double] = [:]) {
            self.modelVersion = modelVersion
            self.modelType = modelType
            self.confidence = confidence
            self.processingTime = processingTime
            self.inputSize = inputSize
            self.timestamp = timestamp
            self.additionalMetrics = additionalMetrics
        }
    }
    
    public enum ModelType: String, CaseIterable {
        case visionHeuristic = "vision-heuristic"
        case visionCoreML = "vision-coreml"
        case visionOptimized = "vision-optimized"
        case audioHeuristic = "audio-heuristic"
        case audioCoreML = "audio-coreml"
        case performanceHeuristic = "performance-heuristic"
        case performanceCoreML = "performance-coreml"
        case transcriptionWhisper = "transcription-whisper"
        case syncCorrelation = "sync-correlation"
        case syncTimecode = "sync-timecode"
        case syncSlate = "sync-slate"
    }
    
    public struct InputSize {
        public let duration: Double // seconds
        public let frameCount: Int?
        public let sampleCount: Int?
        public let resolution: CGSize?
        
        public init(duration: Double, frameCount: Int? = nil, sampleCount: Int? = nil, resolution: CGSize? = nil) {
            self.duration = duration
            self.frameCount = frameCount
            self.sampleCount = sampleCount
            self.resolution = resolution
        }
    }
    
    private var metadataHistory: [InferenceMetadata] = []
    private let maxHistorySize: Int
    
    public init(maxHistorySize: Int = 1000) {
        self.maxHistorySize = maxHistorySize
    }
    
    // MARK: - Recording Methods
    
    public mutating func recordVisionInference(
        modelVersion: String,
        modelType: ModelType,
        confidence: Double,
        processingTime: TimeInterval,
        inputSize: InputSize,
        additionalMetrics: [String: Double] = [:]
    ) {
        let metadata = InferenceMetadata(
            modelVersion: modelVersion,
            modelType: modelType,
            confidence: confidence,
            processingTime: processingTime,
            inputSize: inputSize,
            additionalMetrics: additionalMetrics
        )
        
        addMetadata(metadata)
    }
    
    public mutating func recordAudioInference(
        modelVersion: String,
        modelType: ModelType,
        confidence: Double,
        processingTime: TimeInterval,
        inputSize: InputSize,
        additionalMetrics: [String: Double] = [:]
    ) {
        let metadata = InferenceMetadata(
            modelVersion: modelVersion,
            modelType: modelType,
            confidence: confidence,
            processingTime: processingTime,
            inputSize: inputSize,
            additionalMetrics: additionalMetrics
        )
        
        addMetadata(metadata)
    }
    
    public mutating func recordSyncInference(
        method: ModelType,
        confidence: SyncConfidence,
        processingTime: TimeInterval,
        inputSize: InputSize,
        additionalMetrics: [String: Double] = [:]
    ) {
        let confidenceValue = confidenceToDouble(confidence)
        
        let metadata = InferenceMetadata(
            modelVersion: "sync-v1",
            modelType: method,
            confidence: confidenceValue,
            processingTime: processingTime,
            inputSize: inputSize,
            additionalMetrics: additionalMetrics
        )
        
        addMetadata(metadata)
    }
    
    public mutating func recordTranscriptionInference(
        modelVersion: String,
        confidence: Double,
        processingTime: TimeInterval,
        inputSize: InputSize,
        additionalMetrics: [String: Double] = [:]
    ) {
        let metadata = InferenceMetadata(
            modelVersion: modelVersion,
            modelType: .transcriptionWhisper,
            confidence: confidence,
            processingTime: processingTime,
            inputSize: inputSize,
            additionalMetrics: additionalMetrics
        )
        
        addMetadata(metadata)
    }
    
    // MARK: - Analysis Methods
    
    public func getAverageConfidence(for modelType: ModelType? = nil, since date: Date? = nil) -> Double {
        let filtered = filterMetadata(modelType: modelType, since: date)
        guard !filtered.isEmpty else { return 0 }
        
        return filtered.reduce(0) { $0 + $1.confidence } / Double(filtered.count)
    }
    
    public func getAverageProcessingTime(for modelType: ModelType? = nil, since date: Date? = nil) -> TimeInterval {
        let filtered = filterMetadata(modelType: modelType, since: date)
        guard !filtered.isEmpty else { return 0 }
        
        return filtered.reduce(0) { $0 + $1.processingTime } / Double(filtered.count)
    }
    
    public func getConfidenceTrend(for modelType: ModelType, windowSize: Int = 10) -> [Double] {
        let filtered = metadataHistory.filter { $0.modelType == modelType }
        guard filtered.count >= windowSize else { return [] }
        
        var trends: [Double] = []
        for i in windowSize...filtered.count {
            let window = Array(filtered[(i-windowSize)..<i])
            let avg = window.reduce(0) { $0 + $1.confidence } / Double(window.count)
            trends.append(avg)
        }
        
        return trends
    }
    
    public func getPerformanceMetrics() -> PerformanceReport {
        let grouped = Dictionary(grouping: metadataHistory) { $0.modelType }
        
        var reports: [ModelType: ModelPerformance] = [:]
        
        for (type, metadatas) in grouped {
            let avgConfidence = metadatas.reduce(0) { $0 + $1.confidence } / Double(metadatas.count)
            let avgProcessingTime = metadatas.reduce(0) { $0 + $1.processingTime } / Double(metadatas.count)
            let totalProcessed = metadatas.count
            
            let confidenceByTime = metadatas.sorted { $0.timestamp < $1.timestamp }.map { $0.confidence }
            let trend = calculateTrend(confidenceByTime)
            
            reports[type] = ModelPerformance(
                averageConfidence: avgConfidence,
                averageProcessingTime: avgProcessingTime,
                totalProcessed: totalProcessed,
                confidenceTrend: trend
            )
        }
        
        return PerformanceReport(modelReports: reports, generatedAt: Date())
    }
    
    // MARK: - Private Methods
    
    private mutating func addMetadata(_ metadata: InferenceMetadata) {
        metadataHistory.append(metadata)
        
        // Maintain history size
        if metadataHistory.count > maxHistorySize {
            metadataHistory.removeFirst(metadataHistory.count - maxHistorySize)
        }
    }
    
    private func filterMetadata(modelType: ModelType?, since date: Date?) -> [InferenceMetadata] {
        return metadataHistory.filter { metadata in
            if let modelType = modelType, metadata.modelType != modelType {
                return false
            }
            if let date = date, metadata.timestamp < date {
                return false
            }
            return true
        }
    }
    
    private func confidenceToDouble(_ confidence: SyncConfidence) -> Double {
        switch confidence {
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.5
        case .manualRequired: return 0.3
        case .unsynced: return 0.1
        }
    }
    
    private func calculateTrend(_ values: [Double]) -> TrendDirection {
        guard values.count >= 2 else { return .stable }
        
        let firstHalf = values.prefix(values.count / 2)
        let secondHalf = values.suffix(values.count / 2)
        
        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)
        
        let difference = secondAvg - firstAvg
        
        switch difference {
        case let diff where diff > 0.05:
            return .improving
        case let diff where diff < -0.05:
            return .degrading
        default:
            return .stable
        }
    }
}

// MARK: - Supporting Types

public struct PerformanceReport {
    public let modelReports: [ConfidenceTracker.ModelType: ModelPerformance]
    public let generatedAt: Date
    
    public init(modelReports: [ConfidenceTracker.ModelType: ModelPerformance], generatedAt: Date = Date()) {
        self.modelReports = modelReports
        self.generatedAt = generatedAt
    }
    
    public func generateSummary() -> String {
        var summary = "AI Performance Report\n"
        summary += "=====================\n\n"
        summary += "Generated: \(generatedAt)\n\n"
        
        for (type, performance) in modelReports.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            summary += "\(type.rawValue):\n"
            summary += "  Average Confidence: \(String(format: "%.2f", performance.averageConfidence))\n"
            summary += "  Average Processing Time: \(String(format: "%.3f", performance.averageProcessingTime))s\n"
            summary += "  Total Processed: \(performance.totalProcessed)\n"
            summary += "  Trend: \(performance.confidenceTrend.rawValue)\n\n"
        }
        
        return summary
    }
}

public struct ModelPerformance {
    public let averageConfidence: Double
    public let averageProcessingTime: TimeInterval
    public let totalProcessed: Int
    public let confidenceTrend: TrendDirection
    
    public init(averageConfidence: Double, averageProcessingTime: TimeInterval, 
               totalProcessed: Int, confidenceTrend: TrendDirection) {
        self.averageConfidence = averageConfidence
        self.averageProcessingTime = averageProcessingTime
        self.totalProcessed = totalProcessed
        self.confidenceTrend = confidenceTrend
    }
}

public enum TrendDirection: String {
    case improving = "📈 Improving"
    case degrading = "📉 Degrading"
    case stable = "➡️ Stable"
}

// MARK: - Extension for AIScores

extension AIScores {
    public init(withMetadata metadata: ConfidenceTracker.InferenceMetadata, scores: AIScores) {
        self = scores
        // Store metadata separately or extend AIScores to include it
    }
    
    public func withConfidenceTracking(_ tracker: inout ConfidenceTracker, 
                                      modelType: ConfidenceTracker.ModelType,
                                      modelVersion: String,
                                      processingTime: TimeInterval,
                                      inputSize: ConfidenceTracker.InputSize) {
        tracker.recordVisionInference(
            modelVersion: modelVersion,
            modelType: modelType,
            confidence: Double(composite),
            processingTime: processingTime,
            inputSize: inputSize,
            additionalMetrics: [
                "focus": Double(focus),
                "exposure": Double(exposure),
                "stability": Double(stability),
                "audio": Double(audio)
            ]
        )
    }
}
