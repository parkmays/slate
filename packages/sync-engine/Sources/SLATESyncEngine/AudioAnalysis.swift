import Accelerate
import Foundation

enum AudioAnalysis {
    static func downsample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > targetRate else { return samples }
        let stride = max(1, Int(sourceRate / targetRate))
        if stride == 1 { return samples }

        var result: [Float] = []
        result.reserveCapacity(samples.count / stride)
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + stride)
            let slice = samples[index..<end]
            let mean = slice.reduce(Float.zero, +) / Float(slice.count)
            result.append(mean)
            index += stride
        }
        return result
    }

    static func onsetEnvelope(samples: [Float], sampleRate: Double, windowSeconds: Double = 0.02, hopSeconds: Double = 0.01) -> [Float] {
        let windowSize = max(16, Int(sampleRate * windowSeconds))
        let hopSize = max(8, Int(sampleRate * hopSeconds))
        guard samples.count >= windowSize else { return [] }

        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / hopSize)

        var previousEnergy: Float = 0
        var index = 0
        while index + windowSize <= samples.count {
            let window = Array(samples[index..<(index + windowSize)])
            let energy = rms(window)
            envelope.append(max(0, energy - previousEnergy))
            previousEnergy = energy
            index += hopSize
        }

        return envelope
    }

    static func topPeakIndices(values: [Float], count: Int, minSeparation: Int) -> [Int] {
        guard !values.isEmpty else { return [] }
        let ranked = values.enumerated().sorted { $0.element > $1.element }
        var peaks: [Int] = []
        for candidate in ranked {
            if peaks.allSatisfy({ abs($0 - candidate.offset) >= minSeparation }) {
                peaks.append(candidate.offset)
            }
            if peaks.count == count {
                break
            }
        }
        return peaks.sorted()
    }

    static func slice(_ samples: [Float], center: Int, radius: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let start = max(0, center - radius)
        let end = min(samples.count, center + radius)
        guard start < end else { return [] }
        return Array(samples[start..<end])
    }

    static func preRollNoiseFloor(samples: [Float], center: Int, sampleRate: Double, preRollSeconds: Double) -> Float {
        let preRollLength = Int(preRollSeconds * sampleRate)
        let guardSamples = Int(sampleRate * 0.05)
        let end = max(0, center - guardSamples)
        let start = max(0, end - preRollLength)
        guard start < end else { return rms(samples) }
        return max(rms(Array(samples[start..<end])), 0.0001)
    }

    static func gateTransientWindow(_ window: [Float], noiseFloor: Float) -> [Float] {
        let threshold = max(noiseFloor * 1.5, 0.0003)
        return window.map { sample in
            let magnitude = abs(sample)
            guard magnitude > threshold else { return 0 }
            return sample.sign == .minus ? -(magnitude - threshold) : (magnitude - threshold)
        }
    }

    static func peakProminence(values: [Float], peakIndex: Int) -> Float {
        guard values.indices.contains(peakIndex) else { return 0 }
        let neighborhoodRadius = 4
        let start = max(0, peakIndex - neighborhoodRadius)
        let end = min(values.count, peakIndex + neighborhoodRadius + 1)
        let localMean = mean(Array(values[start..<end]))
        let globalPeak = values.max() ?? 1
        return max(0, values[peakIndex] - localMean) / max(globalPeak, 0.0001)
    }

    static func signalToNoiseRatioDB(signalRMS: Float, noiseFloor: Float) -> Float {
        20 * log10(max(signalRMS, 0.0001) / max(noiseFloor, 0.0001))
    }

    static func bestLag(reference: [Float], comparison: [Float], maxLag: Int) -> (lag: Int, score: Float) {
        guard !reference.isEmpty, !comparison.isEmpty else { return (0, 0) }
        let refMean = mean(reference)
        let cmpMean = mean(comparison)
        let centeredReference = reference.map { $0 - refMean }
        let centeredComparison = comparison.map { $0 - cmpMean }

        var bestLag = 0
        var bestScore = -Float.greatestFiniteMagnitude

        for lag in (-maxLag)...maxLag {
            let ranges = overlapRanges(referenceCount: centeredReference.count, comparisonCount: centeredComparison.count, lag: lag)
            guard ranges.reference.count > 16 else { continue }

            let refSlice = Array(centeredReference[ranges.reference])
            let cmpSlice = Array(centeredComparison[ranges.comparison])
            let score = normalizedCorrelation(refSlice, cmpSlice)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        return (bestLag, bestScore.isFinite ? bestScore : 0)
    }

    static func normalizedCorrelation(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        let lhsEnergy = sqrt(max(vDSP.sum(vDSP.multiply(lhs, lhs)), .leastNormalMagnitude))
        let rhsEnergy = sqrt(max(vDSP.sum(vDSP.multiply(rhs, rhs)), .leastNormalMagnitude))
        let dot = vDSP.dot(lhs, rhs)
        return dot / (lhsEnergy * rhsEnergy)
    }

    static func refineLag(
        reference: [Float],
        comparison: [Float],
        around coarseLag: Int,
        radius: Int
    ) -> (lag: Int, score: Float) {
        guard !reference.isEmpty, !comparison.isEmpty else { return (coarseLag, 0) }
        var best = (lag: coarseLag, score: -Float.greatestFiniteMagnitude)
        for lag in (coarseLag - radius)...(coarseLag + radius) {
            let ranges = overlapRanges(referenceCount: reference.count, comparisonCount: comparison.count, lag: lag)
            guard ranges.reference.count > 32 else { continue }
            let refSlice = Array(reference[ranges.reference])
            let cmpSlice = Array(comparison[ranges.comparison])
            let score = normalizedCorrelation(refSlice, cmpSlice)
            if score > best.score {
                best = (lag, score)
            }
        }
        return (best.lag, best.score.isFinite ? best.score : 0)
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(vDSP.mean(vDSP.multiply(samples, samples)))
    }

    private static func mean(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return vDSP.mean(samples)
    }

    private static func overlapRanges(referenceCount: Int, comparisonCount: Int, lag: Int) -> (reference: Range<Int>, comparison: Range<Int>) {
        if lag >= 0 {
            let length = min(referenceCount, comparisonCount - lag)
            return (0..<max(0, length), lag..<max(lag, lag + length))
        }

        let offset = -lag
        let length = min(referenceCount - offset, comparisonCount)
        return (offset..<max(offset, offset + length), 0..<max(0, length))
    }
}
