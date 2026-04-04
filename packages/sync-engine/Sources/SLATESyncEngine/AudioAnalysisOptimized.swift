import Accelerate
import Foundation

enum AudioAnalysisOptimized {
    
    /// Optimized downsampling using vDSP decimation with anti-aliasing filter
    static func downsample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard !samples.isEmpty, sourceRate > targetRate else { return samples }
        
        let decimationFactor = Int(sourceRate / targetRate)
        guard decimationFactor > 1 else { return samples }
        
        // Use vDSP decimation with proper anti-aliasing
        let outputCount = samples.count / decimationFactor
        var output = [Float](repeating: 0, count: outputCount)
        
        // Create FIR filter coefficients for anti-aliasing
        // Using a simple low-pass FIR filter with Hamming window
        let filterLength = 64
        let cutoff = 0.9 / Float(decimationFactor) // Nyquist frequency of target rate
        let coefficients = generateLowPassFilter(length: filterLength, cutoff: cutoff)
        
        // Apply decimation with filtering
        vDSP.convolve(samples,
                      signalStride: 1,
                      coefficients,
                      coeffStride: 1,
                      result: &output,
                      resultStride: decimationFactor,
                      count: outputCount,
                      coefficientsCount: coefficients.count)
        
        return output
    }
    
    /// Generate FIR low-pass filter coefficients using Hamming window
    private static func generateLowPassFilter(length: Int, cutoff: Float) -> [Float] {
        var coefficients = [Float](repeating: 0, count: length)
        let m = Float(length - 1)
        let halfLength = length / 2
        
        for i in 0..<length {
            let n = Float(i)
            
            // Sinc function
            if i == halfLength {
                coefficients[i] = 2 * cutoff
            } else {
                let arg = Float.pi * (n - m/2) * cutoff
                coefficients[i] = sin(arg) / arg
            }
            
            // Hamming window
            coefficients[i] *= 0.54 - 0.46 * cos(2 * Float.pi * n / m)
        }
        
        // Normalize filter
        let sum = coefficients.reduce(0, +)
        return coefficients.map { $0 / sum }
    }
    
    /// Fast correlation using FFT for large arrays
    static func fastCorrelation(reference: [Float], comparison: [Float], maxLag: Int) -> (lag: Int, score: Float) {
        guard !reference.isEmpty, !comparison.isEmpty else { return (0, 0) }
        
        // For small arrays, use direct correlation
        let minSize = min(reference.count, comparison.count)
        if minSize < 2048 || maxLag < 100 {
            return bestLagDirect(reference: reference, comparison: comparison, maxLag: maxLag)
        }
        
        // Use FFT for larger arrays
        return bestLagFFT(reference: reference, comparison: comparison, maxLag: maxLag)
    }
    
    private static func bestLagDirect(reference: [Float], comparison: [Float], maxLag: Int) -> (lag: Int, score: Float) {
        // Center the signals
        let refMean = mean(reference)
        let cmpMean = mean(comparison)
        
        var centeredReference = [Float](repeating: 0, count: reference.count)
        var centeredComparison = [Float](repeating: 0, count: comparison.count)
        
        vDSP.subtract(refMean, reference, result: &centeredReference)
        vDSP.subtract(cmpMean, comparison, result: &centeredComparison)
        
        var bestLag = 0
        var bestScore: Float = -1
        
        // Pre-compute energies for normalization
        var refEnergy: Float = 0
        vDSP.square(centeredReference, result: &centeredReference)
        vDSP.sum(centeredReference, result: &refEnergy)
        refEnergy = sqrt(refEnergy)
        
        // Restore original reference
        vDSP.add(refMean, centeredReference, result: &centeredReference)
        vDSP.multiply(-1, centeredReference, result: &centeredReference)
        
        for lag in (-maxLag)...maxLag {
            let ranges = overlapRanges(referenceCount: centeredReference.count, comparisonCount: centeredComparison.count, lag: lag)
            guard ranges.reference.count > 16 else { continue }
            
            let refSlice = Array(centeredReference[ranges.reference])
            let cmpSlice = Array(centeredComparison[ranges.comparison])
            
            let score = normalizedCorrelation(refSlice, cmpSlice, refEnergy: refEnergy)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        
        return (bestLag, bestScore.isFinite ? bestScore : 0)
    }
    
    private static func bestLagFFT(reference: [Float], comparison: [Float], maxLag: Int) -> (lag: Int, score: Float) {
        let n = 1 << Int(ceil(log2(Float(Double(reference.count + comparison.count + maxLag)))))
        
        // Prepare FFT setup
        guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(n))), FFTRadix(kFFTRadix2)) else {
            return bestLagDirect(reference: reference, comparison: comparison, maxLag: maxLag)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // Pad signals
        var refPadded = [Float](repeating: 0, count: n * 2)
        var cmpPadded = [Float](repeating: 0, count: n * 2)
        
        // Convert to complex format
        for (i, value) in reference.enumerated() {
            refPadded[i * 2] = value
        }
        
        // Reverse comparison for convolution
        for (i, value) in comparison.enumerated() {
            cmpPadded[(cmpPadded.count / 2 - 1 - i) * 2] = value
        }
        
        // Perform FFT
        var refReal = [Float](repeating: 0, count: n)
        var refImag = [Float](repeating: 0, count: n)
        var cmpReal = [Float](repeating: 0, count: n)
        var cmpImag = [Float](repeating: 0, count: n)
        
        refPadded.withUnsafeBufferPointer { refPtr in
            refReal.withUnsafeMutableBufferPointer { realPtr in
                refImag.withUnsafeMutableBufferPointer { imagPtr in
                    vDSP_fft_zrip(fftSetup, realPtr.baseAddress!, imagPtr.baseAddress!, 2, Int32(log2(Float(n))))
                }
            }
        }
        
        cmpPadded.withUnsafeBufferPointer { cmpPtr in
            cmpReal.withUnsafeMutableBufferPointer { realPtr in
                cmpImag.withUnsafeMutableBufferPointer { imagPtr in
                    vDSP_fft_zrip(fftSetup, realPtr.baseAddress!, imagPtr.baseAddress!, 2, Int32(log2(Float(n))))
                }
            }
        }
        
        // Multiply in frequency domain
        var resultReal = [Float](repeating: 0, count: n)
        var resultImag = [Float](repeating: 0, count: n)
        
        vDSP.multiply(refReal, cmpReal, result: &resultReal)
        vDSP.multiply(refReal, cmpImag, result: &resultImag)
        vDSP.multiply(refImag, cmpReal, result: &resultImag)
        vDSP.multiply(refImag, cmpImag, result: &resultReal)
        
        // Inverse FFT
        resultReal.withUnsafeMutableBufferPointer { realPtr in
            resultImag.withUnsafeMutableBufferPointer { imagPtr in
                vDSP_fft_zrip(fftSetup, realPtr.baseAddress!, imagPtr.baseAddress!, 2, Int32(log2(Float(n))))
                vDSP_fft_zrip(fftSetup, realPtr.baseAddress!, imagPtr.baseAddress!, 2, Int32(log2(Float(n))))
            }
        }
        
        // Find peak in valid range
        let centerOffset = comparison.count - 1
        let searchStart = max(0, centerOffset - maxLag)
        let searchEnd = min(resultReal.count, centerOffset + maxLag + 1)
        
        var bestLag = 0
        var bestScore: Float = -1
        
        for i in searchStart..<searchEnd {
            let lag = i - centerOffset
            if resultReal[i] > bestScore {
                bestScore = resultReal[i]
                bestLag = lag
            }
        }
        
        // Normalize the score
        bestScore = bestScore / Float(n)
        
        return (bestLag, bestScore.isFinite ? bestScore : 0)
    }
    
    private static func normalizedCorrelation(_ lhs: [Float], _ rhs: [Float], refEnergy: Float? = nil) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        
        let lhsEnergy: Float
        if let refEnergy = refEnergy {
            lhsEnergy = refEnergy
        } else {
            var temp = [Float](repeating: 0, count: lhs.count)
            vDSP.multiply(lhs, lhs, result: &temp)
            vDSP.sum(temp, result: &lhsEnergy)
            lhsEnergy = sqrt(lhsEnergy)
        }
        
        var rhsSquared = [Float](repeating: 0, count: rhs.count)
        vDSP.multiply(rhs, rhs, result: &rhsSquared)
        
        var rhsEnergy: Float = 0
        vDSP.sum(rhsSquared, result: &rhsEnergy)
        rhsEnergy = sqrt(rhsEnergy)
        
        guard lhsEnergy > .leastNormalMagnitude, rhsEnergy > .leastNormalMagnitude else { return 0 }
        
        var dot: Float = 0
        vDSP.dot(lhs, rhs, result: &dot)
        
        return dot / (lhsEnergy * rhsEnergy)
    }
    
    // Helper functions
    private static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var result: Float = 0
        vDSP.mean(values, result: &result)
        return result
    }
    
    private static func rms(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        var result: Float = 0
        vDSP.rms(values, result: &result)
        return result
    }
    
    private static func overlapRanges(referenceCount: Int, comparisonCount: Int, lag: Int) -> (reference: Range<Int>, comparison: Range<Int>) {
        switch lag.sign {
        case .plus:
            let refStart = lag
            let refEnd = referenceCount
            let cmpStart = 0
            let cmpEnd = min(comparisonCount, referenceCount - lag)
            return (refStart..<refEnd, cmpStart..<cmpEnd)
        case .minus:
            let refStart = 0
            let refEnd = min(referenceCount, comparisonCount + lag)
            let cmpStart = -lag
            let cmpEnd = comparisonCount
            return (refStart..<refEnd, cmpStart..<cmpEnd)
        case .zero:
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
        self.samplesPerSecond = Double(samplesProcessed) / totalDuration
    }
}
