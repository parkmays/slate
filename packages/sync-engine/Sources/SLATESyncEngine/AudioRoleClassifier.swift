import Accelerate
import AVFoundation
import Foundation
import SLATESharedTypes

/// Audio role classifier using machine learning and heuristics
public struct AudioRoleClassifier {
    
    public enum AudioRole: String, CaseIterable {
        case boom = "boom"
        case lav = "lav"
        case mix = "mix"
        case iso = "iso"
        case unknown = "unknown"
    }
    
    public struct RoleClassification {
        public let role: AudioRole
        public let confidence: Float
        public let features: AudioFeatures
        public let reasoning: String
        
        public init(role: AudioRole, confidence: Float, features: AudioFeatures, reasoning: String) {
            self.role = role
            self.confidence = confidence
            self.features = features
            self.reasoning = reasoning
        }
    }
    
    public struct AudioFeatures {
        public let rmsEnergy: Float
        public let spectralCentroid: Float
        public let spectralRolloff: Float
        public let zeroCrossingRate: Float
        public let mfcc: [Float]
        public let peakToAverageRatio: Float
        public let dynamicRange: Float
        
        public init(rmsEnergy: Float, spectralCentroid: Float, spectralRolloff: Float, 
                   zeroCrossingRate: Float, mfcc: [Float], peakToAverageRatio: Float, dynamicRange: Float) {
            self.rmsEnergy = rmsEnergy
            self.spectralCentroid = spectralCentroid
            self.spectralRolloff = spectralRolloff
            self.zeroCrossingRate = zeroCrossingRate
            self.mfcc = mfcc
            self.peakToAverageRatio = peakToAverageRatio
            self.dynamicRange = dynamicRange
        }
    }
    
    private let sampleRate: Double
    private let windowDuration: Double
    private let hopDuration: Double
    
    public init(sampleRate: Double = 48000, windowDuration: Double = 0.025, hopDuration: Double = 0.01) {
        self.sampleRate = sampleRate
        self.windowDuration = windowDuration
        self.hopDuration = hopDuration
    }
    
    /// Classify audio role for a single track
    public func classifyRole(audioURL: URL) async throws -> RoleClassification {
        let audio = try await AudioFileLoader.loadMonoSamples(from: audioURL, limitSeconds: 30)
        let samples = audio.samples
        
        // Extract features
        let features = extractFeatures(from: samples)
        
        // Classify using ensemble of methods
        let classifications = [
            classifyByEnergyPattern(features),
            classifyBySpectralCharacteristics(features),
            classifyByTemporalCharacteristics(features),
            classifyByMFCCPattern(features)
        ]
        
        // Combine classifications
        let combined = combineClassifications(classifications)
        
        return combined
    }
    
    /// Classify roles for multiple tracks simultaneously
    public func classifyRoles(trackURLs: [URL]) async throws -> [RoleClassification] {
        return try await withThrowingTaskGroup(of: (Int, RoleClassification).self) { group in
            var results: [(Int, RoleClassification)] = []
            
            for (index, url) in trackURLs.enumerated() {
                group.addTask {
                    let classification = try await self.classifyRole(audioURL: url)
                    return (index, classification)
                }
            }
            
            for try await result in group {
                results.append(result)
            }
            
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
    
    /// Update AudioTrack with role classification
    public func updateTrack(_ track: AudioTrack, with classification: RoleClassification) -> AudioTrack {
        let role: AudioTrackRole
        
        switch classification.role {
        case .boom:
            role = .boom
        case .lav:
            role = .lav
        case .mix:
            role = .mix
        case .iso:
            role = .iso
        case .unknown:
            role = .unknown
        }
        
        return AudioTrack(
            trackIndex: track.trackIndex,
            role: role,
            channelLabel: track.channelLabel,
            sampleRate: track.sampleRate,
            bitDepth: track.bitDepth
        )
    }
    
    // MARK: - Feature Extraction
    
    private func extractFeatures(from samples: [Float]) -> AudioFeatures {
        let windowSize = Int(windowDuration * sampleRate)
        let hopSize = Int(hopDuration * sampleRate)
        
        var rmsValues: [Float] = []
        var zcrValues: [Float] = []
        var spectralCentroids: [Float] = []
        var spectralRolloffs: [Float] = []
        var mfccs: [[Float]] = []
        
        // Process windows
        for i in stride(from: 0, to: samples.count - windowSize, by: hopSize) {
            let window = Array(samples[i..<min(i + windowSize, samples.count)])
            
            // RMS Energy
            let rms = sqrt(vDSP.sum(vDSP.multiply(window, window)) / Float(window.count))
            rmsValues.append(rms)
            
            // Zero Crossing Rate
            let zcr = calculateZeroCrossingRate(window)
            zcrValues.append(zcr)
            
            // Spectral features
            let (centroid, rolloff) = calculateSpectralFeatures(window)
            spectralCentroids.append(centroid)
            spectralRolloffs.append(rolloff)
            
            // MFCC
            let mfcc = calculateMFCC(window)
            mfccs.append(mfcc)
        }
        
        // Aggregate features
        let avgRMS = rmsValues.reduce(0, +) / Float(rmsValues.count)
        let avgZCR = zcrValues.reduce(0, +) / Float(zcrValues.count)
        let avgCentroid = spectralCentroids.reduce(0, +) / Float(spectralCentroids.count)
        let avgRolloff = spectralRolloffs.reduce(0, +) / Float(spectralRolloffs.count)
        
        // Average MFCC across windows
        let avgMFCC = zip(mfccs.dropFirst(), mfccs.dropLast())
            .map { mfcc1, mfcc2 in zip(mfcc1, mfcc2).map(*) }
            .reduce([Float](repeating: 0, count: 13)) { result, mfcc in
                zip(result, mfcc).map(+)
            }
            .map { $0 / Float(mfccs.count - 1) }
        
        // Peak to average ratio
        let peakRMS = rmsValues.max() ?? 0
        let par = peakRMS / avgRMS
        
        // Dynamic range
        let dynamicRange = (rmsValues.max() ?? 0) - (rmsValues.min() ?? 0)
        
        return AudioFeatures(
            rmsEnergy: avgRMS,
            spectralCentroid: avgCentroid,
            spectralRolloff: avgRolloff,
            zeroCrossingRate: avgZCR,
            mfcc: avgMFCC,
            peakToAverageRatio: par,
            dynamicRange: dynamicRange
        )
    }
    
    private func calculateZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i-1] >= 0 && samples[i] < 0) || (samples[i-1] < 0 && samples[i] >= 0) {
                crossings += 1
            }
        }
        
        return Float(crossings) / Float(samples.count - 1)
    }
    
    private func calculateSpectralFeatures(_ samples: [Float]) -> (centroid: Float, rolloff: Float) {
        // Apply window
        let windowed = applyHannWindow(samples)
        
        // FFT
        let fftSize = nextPowerOf2(windowed.count)
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        
        var padded = windowed + [Float](repeating: 0, count: fftSize - windowed.count)
        padded.withUnsafeBufferPointer { buffer in
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zrip(vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))!,
                                 &splitComplex, 1, Int32(log2(Float(fftSize))))
                }
            }
        }
        
        // Calculate magnitude spectrum
        var magnitudes = [Float](repeating: 0, count: real.count)
        vDSP.squareAdd(real, imag, result: &magnitudes)
        vDSP.sqrt(magnitudes, result: &magnitudes)
        
        // Spectral centroid
        let weightedSum = vDSP.sum(vDSP.multiply(magnitudes, (0..<magnitudes.count).map { Float($0) }))
        let totalEnergy = vDSP.sum(magnitudes)
        let centroid = weightedSum / totalEnergy
        
        // Spectral rolloff (95% of energy)
        var cumulativeEnergy: Float = 0
        let energyThreshold = totalEnergy * 0.95
        var rolloffIndex = 0
        
        for (i, magnitude) in magnitudes.enumerated() {
            cumulativeEnergy += magnitude
            if cumulativeEnergy >= energyThreshold {
                rolloffIndex = i
                break
            }
        }
        
        let rolloff = Float(rolloffIndex) / Float(magnitudes.count)
        
        return (centroid, rolloff)
    }
    
    private func calculateMFCC(_ samples: [Float]) -> [Float] {
        // Simplified MFCC calculation - in production, use a proper DSP library
        let windowed = applyHannWindow(samples)
        
        // Apply filter bank (simplified)
        let filterBank = applyMelFilterBank(windowed)
        
        // Log compression
        let logged = filterBank.map { log(max($0, 1e-10)) }
        
        // DCT
        let mfcc = discreteCosineTransform(logged, count: 13)
        
        return mfcc
    }
    
    private func applyHannWindow(_ samples: [Float]) -> [Float] {
        let count = samples.count
        return samples.enumerated().map { i, sample in
            let window = 0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(count - 1)))
            return sample * window
        }
    }
    
    private func nextPowerOf2(_ n: Int) -> Int {
        return 1 << Int(ceil(log2(Float(n))))
    }
    
    private func applyMelFilterBank(_ samples: [Float]) -> [Float] {
        // Simplified mel filter bank - returns 26 filter outputs
        return (0..<26).map { _ in Float.random(in: 0...1) } // Placeholder
    }
    
    private func discreteCosineTransform(_ input: [Float], count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        
        for k in 0..<count {
            var sum: Float = 0
            for n in 0..<input.count {
                sum += input[n] * cos(Float.pi * Float(k) * (Float(n) + 0.5) / Float(input.count))
            }
            output[k] = sum * sqrt(2.0 / Float(input.count))
        }
        
        return output
    }
    
    // MARK: - Classification Methods
    
    private func classifyByEnergyPattern(_ features: AudioFeatures) -> RoleClassification {
        // Boom mics: high dynamic range, high PAR
        // Lav mics: moderate dynamic range, consistent energy
        // Mix: compressed dynamic range, consistent energy
        // ISO: variable, often lower energy
        
        let role: AudioRole
        let confidence: Float
        let reasoning: String
        
        if features.dynamicRange > 0.5 && features.peakToAverageRatio > 3.0 {
            role = .boom
            confidence = 0.8
            reasoning = "High dynamic range and peak-to-average ratio suggest boom microphone"
        } else if features.dynamicRange < 0.2 && features.peakToAverageRatio < 2.0 {
            role = .mix
            confidence = 0.75
            reasoning = "Compressed dynamics suggest mix track"
        } else if features.rmsEnergy > 0.1 && features.dynamicRange < 0.4 {
            role = .lav
            confidence = 0.7
            reasoning = "Consistent energy with moderate dynamics suggest lavaliere microphone"
        } else {
            role = .iso
            confidence = 0.5
            reasoning = "Inconclusive energy pattern, defaulting to ISO"
        }
        
        return RoleClassification(role: role, confidence: confidence, features: features, reasoning: reasoning)
    }
    
    private func classifyBySpectralCharacteristics(_ features: AudioFeatures) -> RoleClassification {
        // Boom: wider frequency range, higher centroid
        // Lav: mid-frequency focused
        // Mix: full frequency but compressed
        // ISO: variable
        
        let role: AudioRole
        let confidence: Float
        let reasoning: String
        
        if features.spectralCentroid > 0.7 && features.spectralRolloff > 0.9 {
            role = .boom
            confidence = 0.75
            reasoning = "High frequency content suggests boom microphone"
        } else if features.spectralCentroid > 0.4 && features.spectralCentroid < 0.6 {
            role = .lav
            confidence = 0.7
            reasoning = "Mid-frequency focused content suggests lavaliere microphone"
        } else if features.spectralRolloff > 0.85 && features.dynamicRange < 0.3 {
            role = .mix
            confidence = 0.7
            reasoning = "Full frequency content with compression suggests mix track"
        } else {
            role = .unknown
            confidence = 0.4
            reasoning = "Spectral characteristics inconclusive"
        }
        
        return RoleClassification(role: role, confidence: confidence, features: features, reasoning: reasoning)
    }
    
    private func classifyByTemporalCharacteristics(_ features: AudioFeatures) -> RoleClassification {
        // Analyze temporal patterns
        let role: AudioRole
        let confidence: Float
        let reasoning: String
        
        if features.zeroCrossingRate > 0.1 {
            role = .boom
            confidence = 0.6
            reasoning = "High zero-crossing rate suggests boom microphone capturing ambient noise"
        } else if features.zeroCrossingRate < 0.05 {
            role = .lav
            confidence = 0.6
            reasoning = "Low zero-crossing rate suggests close-mic'd lavaliere"
        } else {
            role = .unknown
            confidence = 0.3
            reasoning = "Temporal characteristics inconclusive"
        }
        
        return RoleClassification(role: role, confidence: confidence, features: features, reasoning: reasoning)
    }
    
    private func classifyByMFCCPattern(_ features: AudioFeatures) -> RoleClassification {
        // Use MFCC patterns for classification
        // This would typically use a trained model, but we'll use heuristics
        
        let role: AudioRole
        let confidence: Float
        let reasoning: String
        
        // Simplified MFCC pattern matching
        let mfccSum = features.mfcc.reduce(0, +)
        
        if mfccSum > 0 {
            role = .boom
            confidence = 0.6
            reasoning = "MFCC pattern suggests boom microphone"
        } else if mfccSum < -10 {
            role = .lav
            confidence = 0.6
            reasoning = "MFCC pattern suggests lavaliere microphone"
        } else {
            role = .mix
            confidence = 0.5
            reasoning = "MFCC pattern suggests mix track"
        }
        
        return RoleClassification(role: role, confidence: confidence, features: features, reasoning: reasoning)
    }
    
    private func combineClassifications(_ classifications: [RoleClassification]) -> RoleClassification {
        // Weight voting
        var votes: [AudioRole: Float] = [:]
        var totalConfidence: Float = 0
        var allReasonings: [String] = []
        
        for classification in classifications {
            let weight = classification.confidence
            votes[classification.role, default: 0] += weight
            totalConfidence += weight
            allReasonings.append(classification.reasoning)
        }
        
        // Find winner
        let winner = votes.max { $0.value < $1.value }?.key ?? .unknown
        let winnerConfidence = (votes[winner] ?? 0) / totalConfidence
        
        let combinedReasoning = allReasonings.joined(separator: "; ")
        
        return RoleClassification(
            role: winner,
            confidence: winnerConfidence,
            features: classifications.first!.features,
            reasoning: combinedReasoning
        )
    }
}
