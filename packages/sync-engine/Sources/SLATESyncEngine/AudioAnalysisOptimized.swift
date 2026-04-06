import Foundation

enum AudioAnalysisOptimized {

    /// Downsample by averaging blocks (anti-aliasing-friendly decimation).
    static func downsample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > targetRate else { return samples }

        let ratio = sourceRate / targetRate
        let step = max(1, Int(round(ratio)))
        var out: [Float] = []
        out.reserveCapacity(samples.count / step)
        var i = 0
        while i < samples.count {
            let end = min(i + step, samples.count)
            var sum: Float = 0
            for j in i..<end {
                sum += samples[j]
            }
            out.append(sum / Float(end - i))
            i = end
        }
        return out
    }

    /// Normalized cross-correlation peak search (direct implementation; fine for typical clip lengths).
    static func fastCorrelation(reference: [Float], comparison: [Float], maxLag: Int) -> (lag: Int, score: Float) {
        guard !reference.isEmpty, !comparison.isEmpty else { return (0, 0) }
        return bestLagDirect(reference: reference, comparison: comparison, maxLag: maxLag)
    }

    private static func bestLagDirect(reference: [Float], comparison: [Float], maxLag: Int) -> (lag: Int, score: Float) {
        let refMean = mean(reference)
        let cmpMean = mean(comparison)
        let ref = reference.map { $0 - refMean }
        let cmp = comparison.map { $0 - cmpMean }

        var refEnergy: Float = 0
        for x in ref {
            refEnergy += x * x
        }
        refEnergy = sqrt(refEnergy)

        var bestLag = 0
        var bestScore: Float = -1

        for lag in (-maxLag)...maxLag {
            let ranges = overlapRanges(referenceCount: ref.count, comparisonCount: cmp.count, lag: lag)
            guard ranges.reference.count > 16 else { continue }

            let refSlice = Array(ref[ranges.reference])
            let cmpSlice = Array(cmp[ranges.comparison])
            let score = normalizedCorrelation(refSlice, cmpSlice, refEnergy: refEnergy)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }

        return (bestLag, bestScore.isFinite ? bestScore : 0)
    }

    private static func normalizedCorrelation(_ lhs: [Float], _ rhs: [Float], refEnergy: Float? = nil) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }

        let lhsEnergy: Float
        if let refEnergy {
            lhsEnergy = refEnergy
        } else {
            var sum: Float = 0
            for x in lhs {
                sum += x * x
            }
            lhsEnergy = sqrt(sum)
        }

        var rhsEnergy: Float = 0
        for x in rhs {
            rhsEnergy += x * x
        }
        rhsEnergy = sqrt(rhsEnergy)

        guard lhsEnergy > .leastNormalMagnitude, rhsEnergy > .leastNormalMagnitude else { return 0 }

        var dot: Float = 0
        for i in lhs.indices {
            dot += lhs[i] * rhs[i]
        }

        return dot / (lhsEnergy * rhsEnergy)
    }

    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var total: Float = 0
        for v in values {
            total += v
        }
        return total / Float(values.count)
    }

    private static func overlapRanges(referenceCount: Int, comparisonCount: Int, lag: Int) -> (reference: Range<Int>, comparison: Range<Int>) {
        if lag > 0 {
            let refStart = lag
            let refEnd = referenceCount
            let cmpStart = 0
            let cmpEnd = min(comparisonCount, referenceCount - lag)
            return (refStart..<refEnd, cmpStart..<cmpEnd)
        } else if lag < 0 {
            let refStart = 0
            let refEnd = min(referenceCount, comparisonCount + lag)
            let cmpStart = -lag
            let cmpEnd = comparisonCount
            return (refStart..<refEnd, cmpStart..<cmpEnd)
        } else {
            let count = min(referenceCount, comparisonCount)
            return (0..<count, 0..<count)
        }
    }
}

// MARK: - Performance Monitoring

public struct SyncPerformanceMetrics {
    public let audioLoadTime: TimeInterval
    public let correlationTime: TimeInterval
    public let totalDuration: TimeInterval
    public let samplesProcessed: Int
    public let samplesPerSecond: Double

    public init(audioLoadTime: TimeInterval, correlationTime: TimeInterval, totalDuration: TimeInterval, samplesProcessed: Int) {
        self.audioLoadTime = audioLoadTime
        self.correlationTime = correlationTime
        self.totalDuration = totalDuration
        self.samplesProcessed = samplesProcessed
        self.samplesPerSecond = totalDuration > 0 ? Double(samplesProcessed) / totalDuration : 0
    }
}
