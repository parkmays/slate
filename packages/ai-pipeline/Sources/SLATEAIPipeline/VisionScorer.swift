import AVFoundation
import CoreGraphics
import CoreImage
import CoreML
import Foundation
import SLATESharedTypes
import Vision

public struct VisionScoreResult: Sendable {
    public let focus: Double
    public let exposure: Double
    public let stability: Double
    public let reasons: [ScoreReason]
    public let modelVersion: String
    public let confidence: Double

    public init(focus: Double, exposure: Double, stability: Double, reasons: [ScoreReason], modelVersion: String = "hybrid-local-v3", confidence: Double = 1.0) {
        self.focus = focus
        self.exposure = exposure
        self.stability = stability
        self.reasons = reasons
        self.modelVersion = modelVersion
        self.confidence = confidence
    }
}

public struct VisionScorer {
    private let sampleFPS: Double
    private let useCoreML: Bool
    private let coreMLManager: CoreMLModelManager
    private let useOptimized: Bool
    private let optimizedScorer: VisionScorerOptimized
    private var degradationManager = GracefulDegradationManager()

    public init(sampleFPS: Double = 2, useCoreML: Bool = true, useOptimized: Bool = true) {
        self.sampleFPS = sampleFPS
        self.useCoreML = useCoreML
        self.coreMLManager = CoreMLModelManager()
        self.useOptimized = useOptimized
        self.optimizedScorer = VisionScorerOptimized(sampleFPS: sampleFPS)
    }

    public func scoreClip(proxyURL: URL, fps: Double) async throws -> VisionScoreResult {
        // Try CoreML first if enabled
        if useCoreML {
            do {
                return try await scoreWithCoreML(proxyURL: proxyURL, fps: fps)
            } catch {
                print("CoreML scoring failed, falling back to optimized: \(error)")
                // Fall back to optimized scoring
            }
        }
        
        // Use optimized scoring if available
        if useOptimized {
            do {
                return try await optimizedScorer.scoreClip(proxyURL: proxyURL, fps: fps)
            } catch {
                print("Optimized scoring failed, falling back to heuristic: \(error)")
                // Fall back to heuristic scoring
            }
        }
        
        // Heuristic scoring (original implementation)
        return try await scoreWithHeuristics(proxyURL: proxyURL, fps: fps)
    }
    
    private func scoreWithCoreML(proxyURL: URL, fps: Double) async throws -> VisionScoreResult {
        // Load models if not already loaded
        try await coreMLManager.loadModels()
        
        // Extract features from video
        let features = try await extractVisionFeatures(from: proxyURL, fps: fps)
        
        // Score with CoreML
        let result = try await coreMLManager.scoreVisionFeatures(features)
        
        return result
    }
    
    private func extractVisionFeatures(from url: URL, fps: Double) async throws -> VisionFeatures {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        
        let duration = try await asset.load(.duration).seconds
        let step = max(1.0 / max(sampleFPS, 1), 0.25)
        let times = stride(from: 0, to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }
        
        var focusMeasures: [Float] = []
        var exposureHistograms: [[Float]] = []
        var motionVectors: [(dx: Float, dy: Float)] = []
        var sharpnessMaps: [Float] = []
        
        var previousImage: CGImage?
        
        for time in times {
            let image = try await generator.image(at: time).image
            let ciImage = CIImage(cgImage: image)
            
            // Extract focus measure using Laplacian variance
            let focusMeasure = extractFocusMeasure(from: ciImage)
            focusMeasures.append(focusMeasure)
            
            // Extract exposure histogram
            let histogram = extractExposureHistogram(from: ciImage)
            exposureHistograms.append(histogram)
            
            // Extract motion vectors
            if let previousImage = previousImage {
                let motion = extractMotionVector(from: previousImage, to: image)
                motionVectors.append(motion)
            }
            previousImage = image
            
            // Extract sharpness map
            let sharpness = extractSharpnessMap(from: ciImage)
            sharpnessMaps.append(contentsOf: sharpness)
        }
        
        // Aggregate features
        let avgFocus = focusMeasures.reduce(0, +) / Float(focusMeasures.count)
        let avgHistogram = averageHistograms(exposureHistograms)
        
        return VisionFeatures(
            focusMeasure: avgFocus,
            exposureHistogram: avgHistogram,
            motionVectors: motionVectors,
            sharpnessMap: Array(sharpnessMaps.prefix(64 * 64)) // Take first 64x64 region
        )
    }
    
    private func extractFocusMeasure(from image: CIImage) -> Float {
        let laplacianFilter = CIFilter(name: "CIConvolution3X3")!
        laplacianFilter.setValue(image, forKey: kCIInputImageKey)
        
        let laplacianKernel = CIVector(values: [-1, -1, -1, -1, 8, -1, -1, -1, -1], count: 9)
        laplacianFilter.setValue(laplacianKernel, forKey: "inputWeights")
        
        guard let output = laplacianFilter.outputImage else { return 0 }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let extent = output.extent
        
        var bitmap = [UInt8](repeating: 0, count: Int(extent.width * extent.height))
        context.render(output,
                     toBitmap: &bitmap,
                     rowBytes: Int(extent.width),
                     bounds: CGRect(origin: .zero, size: extent.size),
                     format: .L8,
                     colorSpace: nil)
        
        // Calculate variance (explicit integer math avoids CoreML MLTensor operator overloads on `+` / `reduce`)
        let n = bitmap.count
        guard n > 0 else { return 0 }
        let sum = bitmap.reduce(0) { $0 + Int($1) }
        let mean = Float(sum) / Float(n)
        var varianceAccum: Float = 0
        for value in bitmap {
            let diff = Float(value) - mean
            varianceAccum += diff * diff
        }
        return varianceAccum / Float(n)
    }
    
    private func extractExposureHistogram(from image: CIImage) -> [Float] {
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let extent = image.extent
        
        var bitmap = [UInt8](repeating: 0, count: Int(extent.width * extent.height * 4))
        context.render(image,
                     toBitmap: &bitmap,
                     rowBytes: Int(extent.width * 4),
                     bounds: CGRect(origin: .zero, size: extent.size),
                     format: .RGBA8,
                     colorSpace: nil)
        
        // Create luminance histogram
        var histogram = [Float](repeating: 0, count: 256)
        let pixelStride = 4
        
        for i in Swift.stride(from: 0, to: bitmap.count, by: pixelStride) {
            let r = Float(bitmap[i])
            let g = Float(bitmap[i + 1])
            let b = Float(bitmap[i + 2])
            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            let index = Int(luminance)
            histogram[index] += 1
        }
        
        // Normalize
        let total = Float(bitmap.count / pixelStride)
        return histogram.map { $0 / total }
    }
    
    private func extractMotionVector(from previous: CGImage, to current: CGImage) -> (dx: Float, dy: Float) {
        // Simple phase correlation for motion estimation
        // In a real implementation, you'd use a more sophisticated optical flow algorithm
        
        _ = CIImage(cgImage: previous)
        _ = CIImage(cgImage: current)
        
        // For now, return a placeholder
        return (dx: 0, dy: 0)
    }
    
    private func extractSharpnessMap(from image: CIImage) -> [Float] {
        let filter = CIFilter(name: "CIConvolution3X3")!
        filter.setValue(image, forKey: kCIInputImageKey)
        
        let kernel = CIVector(values: [0, -1, 0, -1, 4, -1, 0, -1, 0], count: 9)
        filter.setValue(kernel, forKey: "inputWeights")
        
        guard let output = filter.outputImage else { return [] }
        
        let context = CIContext(options: [.useSoftwareRenderer: false])
        let extent = output.extent
        
        var bitmap = [Float](repeating: 0, count: Int(extent.width * extent.height))
        context.render(output,
                     toBitmap: &bitmap,
                     rowBytes: Int(extent.width) * MemoryLayout<Float>.size,
                     bounds: CGRect(origin: .zero, size: extent.size),
                     format: .Rf,
                     colorSpace: nil)
        
        return bitmap
    }
    
    private func averageHistograms(_ histograms: [[Float]]) -> [Float] {
        guard !histograms.isEmpty else { return [Float](repeating: 0, count: 256) }
        
        var result = [Float](repeating: 0, count: 256)
        for histogram in histograms {
            for (i, value) in histogram.enumerated() {
                result[i] += value
            }
        }
        
        let count = Float(histograms.count)
        return result.map { $0 / count }
    }

    private func scoreWithHeuristics(proxyURL: URL, fps: Double) async throws -> VisionScoreResult {
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
                ]
            )
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)

        let step = max(1.0 / max(sampleFPS, 1), 0.25)
        let sampleTimes = stride(from: 0.0, through: max(0, duration - 0.001), by: step).prefix(12)

        var focusScores: [Double] = []
        var exposureScores: [Double] = []
        var frameVectors: [[Float]] = []

        for time in sampleTimes {
            let cgImage = try generator.copyCGImage(
                at: CMTime(seconds: time, preferredTimescale: 600),
                actualTime: nil
            )
            let grayscale = try Self.grayscalePixels(from: cgImage, targetSize: CGSize(width: 96, height: 54))
            focusScores.append(Self.focusScore(from: grayscale, width: 96, height: 54))
            exposureScores.append(Self.exposureScore(from: grayscale))
            frameVectors.append(grayscale)
        }

        let focus = average(focusScores)
        let exposure = average(exposureScores)
        let stability = Self.stabilityScore(from: frameVectors)

        var reasons: [ScoreReason] = []
        if focus < 45 {
            reasons.append(
                .init(
                    dimension: "focus",
                    score: focus,
                    flag: .warning,
                    message: "Proxy frames appear soft; focus confidence is below the preferred threshold."
                )
            )
        }
        if exposure < 45 {
            reasons.append(
                .init(
                    dimension: "exposure",
                    score: exposure,
                    flag: .warning,
                    message: "Proxy frames appear under- or over-exposed."
                )
            )
        }
        if stability < 45 {
            reasons.append(
                .init(
                    dimension: "stability",
                    score: stability,
                    flag: .warning,
                    message: "Frame-to-frame motion exceeded the stability target."
                )
            )
        }
        if reasons.isEmpty {
            reasons.append(
                .init(
                    dimension: "vision",
                    score: (focus + exposure + stability) / 3,
                    flag: .info,
                    message: "Vision scoring completed without advisory issues."
                )
            )
        }

        return VisionScoreResult(
            focus: focus,
            exposure: exposure,
            stability: stability,
            reasons: reasons,
            modelVersion: "hybrid-local-v3",
            confidence: 1.0
        )
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func focusScore(from pixels: [Float], width: Int, height: Int) -> Double {
        guard pixels.count == width * height else { return 0 }
        var energy = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let gx = pixels[index + 1] - pixels[index - 1]
                let gy = pixels[index + width] - pixels[index - width]
                energy += Double(abs(gx) + abs(gy))
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let normalized = energy / Double(count)
        return max(0, min(100, normalized * 620))
    }

    private static func exposureScore(from pixels: [Float]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count)
        let clipped = Double(pixels.filter { $0 < 0.02 || $0 > 0.98 }.count) / Double(pixels.count)
        let meanPenalty = abs(mean - 0.48) * 180
        let clippingPenalty = clipped * 220
        return max(0, min(100, 100 - meanPenalty - clippingPenalty))
    }

    private static func stabilityScore(from frames: [[Float]]) -> Double {
        guard frames.count > 1 else { return 80 }

        var deltas: [Double] = []
        for pair in zip(frames.dropFirst(), frames) {
            let delta = zip(pair.0, pair.1).reduce(0.0) { partial, pixels in
                partial + Double(abs(pixels.0 - pixels.1))
            } / Double(pair.0.count)
            deltas.append(delta)
        }

        let averageDelta = deltas.reduce(0.0, +) / Double(deltas.count)
        return max(0, min(100, 100 - (averageDelta * 260)))
    }

    private static func grayscalePixels(from image: CGImage, targetSize: CGSize) throws -> [Float] {
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        var bytes = Array(repeating: UInt8.zero, count: width * height)

        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw NSError(domain: "VisionScorer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create grayscale context"])
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
        return bytes.map { Float($0) / 255.0 }
    }
}
