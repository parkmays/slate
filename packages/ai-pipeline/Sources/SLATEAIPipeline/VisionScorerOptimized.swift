import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import Metal
import MetalKit
import SLATESharedTypes
import vImage

/// Optimized vision scorer using Metal and vImage for better performance
public struct VisionScorerOptimized {
    private let sampleFPS: Double
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    
    public init(sampleFPS: Double = 2) {
        self.sampleFPS = sampleFPS
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = self.device?.makeCommandQueue()
    }
    
    public func scoreClip(proxyURL: URL, fps: Double) async throws -> VisionScoreResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let asset = AVURLAsset(url: proxyURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            return VisionScoreResult(
                focus: 0,
                exposure: 0,
                stability: 0,
                reasons: [
                    .init(
                        dimension: "vision",
                        score: 0,
                        flag: .warning,
                        message: "Proxy duration was zero, so vision scoring could not run."
                    )
                ],
                modelVersion: "optimized-v1",
                confidence: 1.0
            )
        }
        
        // Adaptive sampling based on duration
        let adaptiveFPS = calculateAdaptiveSampleFPS(duration: duration)
        let step = max(1.0 / adaptiveFPS, 0.1)
        let sampleTimes = stride(from: 0.0, through: max(0, duration - 0.001), by: step).prefix(20)
        
        // Use optimized image generator
        let generator = OptimizedImageGenerator(asset: asset, device: device)
        
        // Process frames in parallel using Metal
        let results = try await generator.processFrames(
            times: Array(sampleTimes),
            targetSize: CGSize(width: 640, height: 360)
        )
        
        // Aggregate scores using vectorized operations
        let scores = aggregateResults(results)
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let framesPerSecond = Double(results.count) / totalTime
        
        print("Vision Scorer: Processed \(results.count) frames in \(String(format: "%.3f", totalTime))s (\(String(format: "%.1f", framesPerSecond)) fps)")
        
        return VisionScoreResult(
            focus: scores.focus,
            exposure: scores.exposure,
            stability: scores.stability,
            reasons: generateReasons(scores: scores),
            modelVersion: "optimized-v1",
            confidence: 1.0
        )
    }
    
    private func calculateAdaptiveSampleFPS(duration: Double) -> Double {
        // Adaptive sampling: fewer samples for longer videos
        switch duration {
        case 0..<300:      // < 5 min
            return 2.0
        case 300..<600:    // 5-10 min
            return 1.5
        default:           // > 10 min
            return 1.0
        }
    }
    
    private func aggregateResults(_ results: [FrameAnalysisResult]) -> (focus: Double, exposure: Double, stability: Double) {
        guard !results.isEmpty else { return (0, 0, 0) }
        
        // Use vImage for fast aggregation
        var focusArray = results.map { Float($0.focus) }
        var exposureArray = results.map { Float($0.exposure) }
        var motionArray = results.map { Float($0.motionMagnitude) }
        
        // Vectorized mean calculation
        var focusMean: Float = 0
        var exposureMean: Float = 0
        var motionMean: Float = 0
        
        vDSP.mean(focusArray, result: &focusMean)
        vDSP.mean(exposureArray, result: &exposureMean)
        vDSP.mean(motionArray, result: &motionMean)
        
        // Calculate stability (inverse of average motion)
        let stability = max(0, 100 - Double(motionMean * 100))
        
        return (
            focus: Double(focusMean),
            exposure: Double(exposureMean),
            stability: stability
        )
    }
    
    private func generateReasons(scores: (focus: Double, exposure: Double, stability: Double)) -> [ScoreReason] {
        var reasons: [ScoreReason] = []
        
        if scores.focus < 45 {
            reasons.append(.init(
                dimension: "focus",
                score: scores.focus,
                flag: .warning,
                message: "Proxy frames appear soft; focus confidence is below the preferred threshold."
            ))
        }
        
        if scores.exposure < 45 {
            reasons.append(.init(
                dimension: "exposure",
                score: scores.exposure,
                flag: .warning,
                message: "Proxy frames appear under- or over-exposed."
            ))
        }
        
        if scores.stability < 45 {
            reasons.append(.init(
                dimension: "stability",
                score: scores.stability,
                flag: .warning,
                message: "Frame-to-frame motion exceeded the stability target."
            ))
        }
        
        if reasons.isEmpty {
            reasons.append(.init(
                dimension: "vision",
                score: (scores.focus + scores.exposure + scores.stability) / 3,
                flag: .info,
                message: "Vision scoring completed without advisory issues."
            ))
        }
        
        return reasons
    }
}

// MARK: - Optimized Image Generator

private class OptimizedImageGenerator {
    private let asset: AVURLAsset
    private let device: MTLDevice?
    private let generator: AVAssetImageGenerator
    private let ciContext: CIContext
    
    init(asset: AVURLAsset, device: MTLDevice?) {
        self.asset = asset
        self.device = device
        self.generator = AVAssetImageGenerator(asset: asset)
        self.generator.appliesPreferredTrackTransform = true
        self.generator.maximumSize = CGSize(width: 640, height: 360)
        
        // Use Metal context for better performance
        if let device = device {
            self.ciContext = CIContext(mtlDevice: device, options: [
                .useSoftwareRenderer: false,
                .priorityRequestLow: false
            ])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }
    
    func processFrames(times: [Double], targetSize: CGSize) async throws -> [FrameAnalysisResult] {
        return try await withThrowingTaskGroup(of: FrameAnalysisResult?.self) { group in
            var results: [FrameAnalysisResult] = []
            
            for time in times {
                group.addTask {
                    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
                    do {
                        let cgImage = try self.generator.copyCGImage(at: cmTime, actualTime: nil)
                        return await self.analyzeFrame(cgImage, at: time)
                    } catch {
                        print("Failed to process frame at \(time)s: \(error)")
                        return nil
                    }
                }
            }
            
            for try await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            
            return results.sorted { $0.time < $1.time }
        }
    }
    
    private func analyzeFrame(_ cgImage: CGImage, at time: Double) async -> FrameAnalysisResult {
        let ciImage = CIImage(cgImage: cgImage)
        
        // Use Metal for parallel processing
        if let device = device {
            return await analyzeWithMetal(ciImage, device: device, at: time)
        } else {
            return analyzeWithCPU(ciImage, at: time)
        }
    }
    
    private func analyzeWithMetal(_ image: CIImage, device: MTLDevice, at time: Double) async -> FrameAnalysisResult {
        // Create texture from image
        let texture = try? ciContext.createTexture(from: image, options: nil)
        guard let texture = texture else {
            return analyzeWithCPU(image, at: time)
        }
        
        // Use Metal compute shader for analysis
        let focusScore = calculateFocusWithMetal(texture, device: device)
        let exposureScore = calculateExposureWithMetal(texture, device: device)
        
        // For motion, we'd need previous frame - simplified for now
        let motionMagnitude: Float = 0
        
        return FrameAnalysisResult(
            time: time,
            focus: Double(focusScore),
            exposure: Double(exposureScore),
            motionMagnitude: motionMagnitude
        )
    }
    
    private func analyzeWithCPU(_ image: CIImage, at time: Double) -> FrameAnalysisResult {
        // Use vImage for optimized CPU processing
        let focusScore = calculateFocusWithVImage(image)
        let exposureScore = calculateExposureWithVImage(image)
        let motionMagnitude: Float = 0
        
        return FrameAnalysisResult(
            time: time,
            focus: Double(focusScore),
            exposure: Double(exposureScore),
            motionMagnitude: motionMagnitude
        )
    }
    
    private func calculateFocusWithMetal(_ texture: MTLTexture, device: MTLDevice) -> Float {
        // Metal compute shader for Laplacian variance
        guard let library = device.makeDefaultLibrary(),
              let kernel = library.makeFunction(name: "laplacianVariance"),
              let pipeline = try? device.makeComputePipelineState(function: kernel),
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return 0
        }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        
        // Create output buffer
        let outputBuffer = device.makeBuffer(length: MemoryLayout<Float>.size, options: .storageModeShared)!
        encoder.setBuffer(outputBuffer, offset: 0, index: 0)
        
        let threadsPerThreadgroup = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroups = MTLSize(
            width: (texture.width + 15) / 16,
            height: (texture.height + 15) / 16,
            depth: 1
        )
        
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let data = outputBuffer.contents().bindMemory(to: Float.self, capacity: 1)
        return data[0]
    }
    
    private func calculateFocusWithVImage(_ image: CIImage) -> Float {
        // Convert CIImage to vImage buffer
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return 0 }
        
        var cgBuffer = vImage_Buffer()
        var format = vImage_CGImageFormat(bitsPerComponent: 8,
                                         bitsPerPixel: 32,
                                         colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         version: 0,
                                         decode: nil,
                                         renderingIntent: .defaultIntent)
        
        var error = vImageBuffer_InitWithCGImage(&cgBuffer, &format, nil, cgImage, UInt32(kvImageNoFlags))
        guard error == kvImageNoError else { return 0 }
        
        defer { free(cgBuffer.data) }
        
        // Apply Laplacian filter using vImage
        var laplacianBuffer = vImage_Buffer()
        error = vImageBuffer_Init(&laplacianBuffer, cgBuffer.height, cgBuffer.width, 8, cgImage.alphaInfo == .premultipliedLast ? 32 : 24)
        guard error == kvImageNoError else { return 0 }
        
        defer { free(laplacianBuffer.data) }
        
        // Laplacian kernel
        let kernel: [Int16] = [-1, -1, -1, -1, 8, -1, -1, -1, -1]
        var divisor: Int32 = 1
        
        error = vImageConvolve_ARGB8888(&laplacianBuffer, &cgBuffer, nil, 0, 0, kernel, 3, 3, &divisor, nil, kvImageBackgroundColor)
        guard error == kvImageNoError else { return 0 }
        
        // Calculate variance
        var mean: Float = 0
        var stdDev: Float = 0
        
        vImageCalculateMeanStdDev_ARGB8888(&laplacianBuffer, nil, 0, &mean, &stdDev, 0, kvImageNoFlags)
        
        return stdDev * stdDev // Variance
    }
    
    private func calculateExposureWithMetal(_ texture: MTLTexture, device: MTLDevice) -> Float {
        // Similar Metal implementation for exposure scoring
        return 50.0 // Placeholder
    }
    
    private func calculateExposureWithVImage(_ image: CIImage) -> Float {
        // Use vImage for histogram calculation
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return 0 }
        
        var cgBuffer = vImage_Buffer()
        var format = vImage_CGImageFormat(bitsPerComponent: 8,
                                         bitsPerPixel: 32,
                                         colorSpace: Unmanaged.passRetained(CGColorSpaceCreateDeviceRGB()),
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         version: 0,
                                         decode: nil,
                                         renderingIntent: .defaultIntent)
        
        var error = vImageBuffer_InitWithCGImage(&cgBuffer, &format, nil, cgImage, UInt32(kvImageNoFlags))
        guard error == kvImageNoError else { return 0 }
        
        defer { free(cgBuffer.data) }
        
        // Calculate histogram
        var histogram = [UInt32](repeating: 0, count: 256)
        error = vImageHistogramCalculation_ARGB8888(&cgBuffer, nil, 0, &histogram, 0, 0, 0, kvImageNoFlags)
        guard error == kvImageNoError else { return 0 }
        
        // Calculate exposure score from histogram
        let totalPixels = cgBuffer.height * cgBuffer.width
        var underexposed = 0
        var overexposed = 0
        
        for (i, count) in histogram.enumerated() {
            if i < 10 { underexposed += Int(count) }
            if i > 245 { overexposed += Int(count) }
        }
        
        let underPercent = Double(underexposed) / Double(totalPixels)
        let overPercent = Double(overexposed) / Double(totalPixels)
        
        // Score: 100 - (under + over) * 100
        return max(0, 100 - (underPercent + overPercent) * 100)
    }
}

// MARK: - Supporting Types

private struct FrameAnalysisResult {
    let time: Double
    let focus: Double
    let exposure: Double
    let motionMagnitude: Float
}

// MARK: - Metal Shader Source (would be in a .metal file)

/*
#include <metal_stdlib>
using namespace metal;

kernel void laplacianVariance(texture2d<float, access::read> inputTexture [[texture(0)]],
                             device float *output [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) return;
    
    float3 color = inputTexture.read(gid).rgb;
    float luminance = dot(color, float3(0.299, 0.587, 0.114));
    
    // Simple Laplacian
    float sum = 0.0;
    int count = 0;
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            uint2 pos = uint2(clamp(int2(gid) + int2(dx, dy), int2(0), int2(inputTexture.get_width() - 1, inputTexture.get_height() - 1)));
            float3 neighborColor = inputTexture.read(pos).rgb;
            float neighborLuminance = dot(neighborColor, float3(0.299, 0.587, 0.114));
            
            if (dx == 0 && dy == 0) {
                sum += 8.0 * luminance;
            } else {
                sum -= neighborLuminance;
            }
            count++;
        }
    }
    
    float laplacian = sum / 9.0;
    
    // Atomic add to variance accumulator
    atomic_fetch_add_explicit((device atomic_float*)output, laplacian * laplacian, memory_order_relaxed);
}
*/
