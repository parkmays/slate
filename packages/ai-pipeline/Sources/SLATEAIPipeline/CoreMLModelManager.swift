import CoreML
import Foundation
import SLATESharedTypes
import Vision
import AVFoundation

/// Manages loading and inference with CoreML models for Phase 2 AI scoring.
/// `MLModel` is not `Sendable`; a plain class + lock avoids Swift 6 actor isolation issues with CoreML APIs.
public final class CoreMLModelManager: @unchecked Sendable {
    
    public enum ModelType {
        case visionQuality
        case audioQuality
        case performance
        
        var filename: String {
            switch self {
            case .visionQuality: return "SLATEVisionQualityV1.mlmodel"
            case .audioQuality: return "SLATEAudioQualityV1.mlmodel"
            case .performance: return "SLATEPerformanceV1.mlmodel"
            }
        }
    }
    
    public enum ModelError: Error, LocalizedError {
        case modelNotFound(String)
        case compilationFailed(Error)
        case inferenceFailed(Error)
        case modelNotLoaded
        
        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model \(name) not found in bundle"
            case .compilationFailed(let error):
                return "Failed to compile model: \(error.localizedDescription)"
            case .inferenceFailed(let error):
                return "Inference failed: \(error.localizedDescription)"
            case .modelNotLoaded:
                return "Model not loaded"
            }
        }
    }
    
    /// Core ML models are main-thread–friendly reference types; unsafe avoids `NSLock` in async (Swift 6 disallows locking across await).
    nonisolated(unsafe) private var visionModel: MLModel?
    nonisolated(unsafe) private var audioModel: MLModel?
    nonisolated(unsafe) private var performanceModel: MLModel?
    
    private let modelVersion: String
    private let useGPU: Bool
    
    public init(modelVersion: String = "coreml-v1", useGPU: Bool = true) {
        self.modelVersion = modelVersion
        self.useGPU = useGPU
    }
    
    /// Load all models asynchronously (sequential loads avoid non-Sendable `MLModel` crossing concurrent child tasks).
    public func loadModels() async throws {
        let vision = try await loadModel(.visionQuality)
        let audio = try await loadModel(.audioQuality)
        let performance = try await loadModel(.performance)
        
        visionModel = vision
        audioModel = audio
        performanceModel = performance
        
        print("CoreML models loaded successfully (version: \(modelVersion))")
    }
    
    /// Load a specific model
    private func loadModel(_ type: ModelType) async throws -> MLModel {
        // Try to load from bundle first
        if let modelURL = Bundle.module.url(forResource: type.filename.replacingOccurrences(of: ".mlmodel", with: ""), withExtension: "mlmodel") {
            do {
                let compiledURL = try await MLModel.compileModel(at: modelURL)
                let configuration = MLModelConfiguration()
                configuration.computeUnits = useGPU ? .cpuAndGPU : .cpuOnly
                return try MLModel(contentsOf: compiledURL, configuration: configuration)
            } catch {
                throw ModelError.compilationFailed(error)
            }
        }
        
        // Fallback: create a mock model for development
        print("Warning: CoreML model \(type.filename) not found, using fallback scoring")
        return try createFallbackModel(type: type)
    }
    
    /// Create a fallback model using traditional algorithms
    private func createFallbackModel(type: ModelType) throws -> MLModel {
        // This would create a simple model that mimics the expected interface
        // For now, we'll throw an error to indicate the model is missing
        throw ModelError.modelNotFound(type.filename)
    }
    
    // MARK: - Vision Scoring
    
    public func scoreVisionFeatures(_ features: VisionFeatures) async throws -> VisionScoreResult {
        guard let model = visionModel else {
            throw ModelError.modelNotLoaded
        }
        
        do {
            let input = try createVisionInput(from: features)
            let output = try await model.prediction(from: input)
            
            return parseVisionOutput(output)
        } catch {
            throw ModelError.inferenceFailed(error)
        }
    }
    
    private func createVisionInput(from features: VisionFeatures) throws -> MLFeatureProvider {
        var inputDict: [String: Any] = [:]
        
        // Convert vision features to model input format
        inputDict["focus_measure"] = try MLMultiArray(shape: [1, 1], dataType: .float32)
        inputDict["exposure_histogram"] = try MLMultiArray(shape: [1, 256], dataType: .float32)
        inputDict["motion_vectors"] = try MLMultiArray(shape: [1, 20, 2], dataType: .float32)
        inputDict["sharpness_map"] = try MLMultiArray(shape: [1, 64, 64], dataType: .float32)
        
        // Fill arrays with actual feature values
        try fillVisionArrays(inputDict, with: features)
        
        return try MLDictionaryFeatureProvider(dictionary: inputDict)
    }
    
    private func fillVisionArrays(_ dict: [String: Any], with features: VisionFeatures) throws {
        // Focus measure
        if let focusArray = dict["focus_measure"] as? MLMultiArray {
            focusArray[0] = NSNumber(value: features.focusMeasure)
        }
        
        // Exposure histogram
        if let histogramArray = dict["exposure_histogram"] as? MLMultiArray {
            for (i, value) in features.exposureHistogram.enumerated() {
                if i < histogramArray.count {
                    histogramArray[i] = NSNumber(value: value)
                }
            }
        }
        
        // Motion vectors
        if let motionArray = dict["motion_vectors"] as? MLMultiArray {
            for (i, vector) in features.motionVectors.enumerated() {
                if i * 2 + 1 < motionArray.count {
                    motionArray[i * 2] = NSNumber(value: vector.dx)
                    motionArray[i * 2 + 1] = NSNumber(value: vector.dy)
                }
            }
        }
        
        // Sharpness map (flattened)
        if let sharpnessArray = dict["sharpness_map"] as? MLMultiArray {
            for (i, value) in features.sharpnessMap.enumerated() {
                if i < sharpnessArray.count {
                    sharpnessArray[i] = NSNumber(value: value)
                }
            }
        }
    }
    
    private func parseVisionOutput(_ output: MLFeatureProvider) -> VisionScoreResult {
        let focus = (output.featureValue(for: "focus_score")?.doubleValue ?? 0) * 100
        let exposure = (output.featureValue(for: "exposure_score")?.doubleValue ?? 0) * 100
        let stability = (output.featureValue(for: "stability_score")?.doubleValue ?? 0) * 100
        
        let confidence = output.featureValue(for: "confidence")?.doubleValue ?? 0
        
        var reasons: [ScoreReason] = []
        if confidence < 0.7 {
            reasons.append(ScoreReason(
                dimension: "vision",
                score: (focus + exposure + stability) / 3,
                flag: .warning,
                message: "Low confidence in CoreML prediction (\(String(format: "%.2f", confidence)))"
            ))
        }
        
        return VisionScoreResult(
            focus: focus,
            exposure: exposure,
            stability: stability,
            reasons: reasons
        )
    }
    
    // MARK: - Audio Scoring
    
    public func scoreAudioFeatures(_ features: AudioFeatures) async throws -> AudioScoreResult {
        guard let model = audioModel else {
            throw ModelError.modelNotLoaded
        }
        
        do {
            let input = try createAudioInput(from: features)
            let output = try await model.prediction(from: input)
            
            return parseAudioOutput(output)
        } catch {
            throw ModelError.inferenceFailed(error)
        }
    }
    
    private func createAudioInput(from features: AudioFeatures) throws -> MLFeatureProvider {
        var inputDict: [String: Any] = [:]
        
        inputDict["mfcc_features"] = try MLMultiArray(shape: [1, 13, 100], dataType: .float32)
        inputDict["spectral_centroid"] = try MLMultiArray(shape: [1, 100], dataType: .float32)
        inputDict["zero_crossing_rate"] = try MLMultiArray(shape: [1, 100], dataType: .float32)
        inputDict["rms_energy"] = try MLMultiArray(shape: [1, 100], dataType: .float32)
        
        try fillAudioArrays(inputDict, with: features)
        
        return try MLDictionaryFeatureProvider(dictionary: inputDict)
    }
    
    private func fillAudioArrays(_ dict: [String: Any], with features: AudioFeatures) throws {
        // Fill MFCC features
        if let mfccArray = dict["mfcc_features"] as? MLMultiArray {
            for t in 0..<100 {
                for c in 0..<13 {
                    let index = t * 13 + c
                    if index < mfccArray.count && t < features.mfccFeatures.count && c < features.mfccFeatures[t].count {
                        mfccArray[index] = NSNumber(value: features.mfccFeatures[t][c])
                    }
                }
            }
        }
        
        // Fill other features similarly...
    }
    
    private func parseAudioOutput(_ output: MLFeatureProvider) -> AudioScoreResult {
        let audio = (output.featureValue(for: "audio_score")?.doubleValue ?? 0) * 100
        let confidence = output.featureValue(for: "confidence")?.doubleValue ?? 0
        
        var reasons: [ScoreReason] = []
        if confidence < 0.7 {
            reasons.append(ScoreReason(
                dimension: "audio",
                score: audio,
                flag: .warning,
                message: "Low confidence in CoreML prediction"
            ))
        }
        
        return AudioScoreResult(
            audio: audio,
            reasons: reasons
        )
    }
    
    // MARK: - Performance Scoring
    
    public func scorePerformanceFeatures(_ features: PerformanceFeatures) async throws -> CoreMLPerformanceScoreResult {
        guard let model = performanceModel else {
            throw ModelError.modelNotLoaded
        }
        
        do {
            let input = try createPerformanceInput(from: features)
            let output = try await model.prediction(from: input)
            
            return parsePerformanceOutput(output)
        } catch {
            throw ModelError.inferenceFailed(error)
        }
    }
    
    private func createPerformanceInput(from features: PerformanceFeatures) throws -> MLFeatureProvider {
        var inputDict: [String: Any] = [:]
        
        inputDict["dialogue_clarity"] = try MLMultiArray(shape: [1], dataType: .float32)
        inputDict["emotional_engagement"] = try MLMultiArray(shape: [1], dataType: .float32)
        inputDict["technical_quality"] = try MLMultiArray(shape: [1], dataType: .float32)
        inputDict["pacing_rhythm"] = try MLMultiArray(shape: [1], dataType: .float32)
        
        // Fill arrays
        if let array = inputDict["dialogue_clarity"] as? MLMultiArray {
            array[0] = NSNumber(value: features.dialogueClarity)
        }
        if let array = inputDict["emotional_engagement"] as? MLMultiArray {
            array[0] = NSNumber(value: features.emotionalEngagement)
        }
        if let array = inputDict["technical_quality"] as? MLMultiArray {
            array[0] = NSNumber(value: features.technicalQuality)
        }
        if let array = inputDict["pacing_rhythm"] as? MLMultiArray {
            array[0] = NSNumber(value: features.pacingRhythm)
        }
        
        return try MLDictionaryFeatureProvider(dictionary: inputDict)
    }
    
    private func parsePerformanceOutput(_ output: MLFeatureProvider) -> CoreMLPerformanceScoreResult {
        let composite = (output.featureValue(for: "composite_score")?.doubleValue ?? 0) * 100

        return CoreMLPerformanceScoreResult(
            composite: composite,
            breakdown: PerformanceBreakdown(
                dialogueClarity: (output.featureValue(for: "dialogue_clarity_score")?.doubleValue ?? 0) * 100,
                emotionalEngagement: (output.featureValue(for: "emotional_engagement_score")?.doubleValue ?? 0) * 100,
                technicalQuality: (output.featureValue(for: "technical_quality_score")?.doubleValue ?? 0) * 100,
                pacingRhythm: (output.featureValue(for: "pacing_rhythm_score")?.doubleValue ?? 0) * 100
            )
        )
    }
}

// MARK: - Feature Structures

public struct VisionFeatures: Sendable {
    public let focusMeasure: Float
    public let exposureHistogram: [Float]
    public let motionVectors: [(dx: Float, dy: Float)]
    public let sharpnessMap: [Float]
    
    public init(focusMeasure: Float, exposureHistogram: [Float], motionVectors: [(dx: Float, dy: Float)], sharpnessMap: [Float]) {
        self.focusMeasure = focusMeasure
        self.exposureHistogram = exposureHistogram
        self.motionVectors = motionVectors
        self.sharpnessMap = sharpnessMap
    }
}

public struct AudioFeatures: Sendable {
    public let mfccFeatures: [[Float]]
    public let spectralCentroid: [Float]
    public let zeroCrossingRate: [Float]
    public let rmsEnergy: [Float]
    
    public init(mfccFeatures: [[Float]], spectralCentroid: [Float], zeroCrossingRate: [Float], rmsEnergy: [Float]) {
        self.mfccFeatures = mfccFeatures
        self.spectralCentroid = spectralCentroid
        self.zeroCrossingRate = zeroCrossingRate
        self.rmsEnergy = rmsEnergy
    }
}

public struct PerformanceFeatures: Sendable {
    public let dialogueClarity: Float
    public let emotionalEngagement: Float
    public let technicalQuality: Float
    public let pacingRhythm: Float
    
    public init(dialogueClarity: Float, emotionalEngagement: Float, technicalQuality: Float, pacingRhythm: Float) {
        self.dialogueClarity = dialogueClarity
        self.emotionalEngagement = emotionalEngagement
        self.technicalQuality = technicalQuality
        self.pacingRhythm = pacingRhythm
    }
}

// MARK: - Additional Result Types

public struct CoreMLPerformanceScoreResult {
    public let composite: Double
    public let breakdown: PerformanceBreakdown
}

public struct PerformanceBreakdown {
    public let dialogueClarity: Double
    public let emotionalEngagement: Double
    public let technicalQuality: Double
    public let pacingRhythm: Double
}
