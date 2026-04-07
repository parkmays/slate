import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import Metal
import MetalKit
import SLATESharedTypes

// MARK: - ProxyLUT

/// Identifies the viewing LUT applied (or not) during proxy generation.
/// Values mirror data-model.json `proxyLUT` field.
public enum ProxyLUT: String, Sendable {
    case arriLogC3Rec709    = "arri_logc3_rec709"
    case bmFilmGen5Rec709   = "bm_film_gen5_rec709"
    case redIPP2Rec709      = "red_ipp2_rec709"
    case none               = "none"
    /// Sentinel stored in `proxyLUT` when baking a user-supplied `.cube` from `customProxyLUTPath`.
    case customCube         = "custom_cube"

    /// Human-readable output color space tag written to `proxyColorSpace`.
    public var proxyColorSpace: String {
        switch self {
        case .none: return "log"
        case .customCube: return "rec709"
        default:    return "rec709"
        }
    }
}

public struct LUTManager {
    private static let device = MTLCreateSystemDefaultDevice()!
    private static let context = CIContext(mtlDevice: device)

    // MARK: - Format → LUT mapping

    /// Returns the appropriate viewing LUT for a given source format.
    /// ProRes / H.264 / MXF are already Rec.709 — no LUT needed (pass-through).
    public static func lut(for format: SourceFormat) -> ProxyLUT {
        switch format {
        case .arriraw:              return .arriLogC3Rec709
        case .braw:                 return .bmFilmGen5Rec709
        case .r3d:                  return .redIPP2Rec709
        case .proRes422HQ, .h264, .mxf: return .none
        }
    }

    // MARK: - Public apply entry point

    /// Applies the correct viewing LUT for `lut` to `sampleBuffer`.
    /// Returns `nil` on any failure (caller should fall back to the original buffer).
    /// For `.none` (pass-through formats) returns `nil` — caller keeps the original.
    public static func applyProxyLUT(to sampleBuffer: CMSampleBuffer, lut: ProxyLUT) -> CMSampleBuffer? {
        applyProxyLUT(to: sampleBuffer, lut: lut, customCubeURL: nil)
    }

    /// Applies a user `.cube` from disk (when `lut` is `.customCube` and URL is readable).
    public static func applyProxyLUT(
        to sampleBuffer: CMSampleBuffer,
        lut: ProxyLUT,
        customCubeURL: URL?
    ) -> CMSampleBuffer? {
        guard lut != .none else { return nil }   // pass-through — no processing needed
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)

        let transformed: CIImage
        if lut == .customCube {
            guard let customCubeURL else { return nil }
            if let cubeFilter = buildCubeFilter(fromCubeURL: customCubeURL, input: ciImage) {
                transformed = cubeFilter
            } else {
                return nil
            }
        } else if let cubeFilter = buildCubeFilter(lut: lut, input: ciImage) {
            transformed = cubeFilter
        } else {
            transformed = parametricRec709Approximation(for: lut, input: ciImage)
        }

        guard let outputPixelBuffer = createPixelBuffer(from: imageBuffer) else { return nil }

        guard let rec709 = CGColorSpace(name: CGColorSpace.itur_709) else { return nil }
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: CVPixelBufferGetWidth(imageBuffer),
            height: CVPixelBufferGetHeight(imageBuffer)
        )
        context.render(transformed, to: outputPixelBuffer, bounds: bounds, colorSpace: rec709)

        return rebuildSampleBuffer(from: outputPixelBuffer, timing: sampleBuffer)
    }

    // MARK: - Legacy pass-through (kept for backward compatibility — unused internally)

    public static func applyProxyLUT(to sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        return nil   // callers should switch to applyProxyLUT(to:lut:)
    }

    // MARK: - Private helpers

    /// Loads a 3D .cube LUT from the app bundle and wraps it in a CIColorCubeWithColorSpace filter.
    private static func buildCubeFilter(lut: ProxyLUT, input: CIImage) -> CIImage? {
        guard let cubeURL = bundledLUTURL(for: lut) else { return nil }
        return buildCubeFilter(fromCubeURL: cubeURL, input: input)
    }

    private static func buildCubeFilter(fromCubeURL: URL, input: CIImage) -> CIImage? {
        guard let cubeData = try? Data(contentsOf: fromCubeURL),
              let (lutData, dimension) = parseCUBEData(cubeData) else {
            return nil
        }

        let rec709 = CGColorSpace(name: CGColorSpace.itur_709)!
        return input.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData":      lutData as NSData,
            "inputColorSpace":    rec709
        ])
    }

    // Internal test seam: validate packaged LUT discovery without invoking CI filters.
    static func bundledLUTURL(for lut: ProxyLUT) -> URL? {
        let resourceName: String
        switch lut {
        case .arriLogC3Rec709:  resourceName = "arri_logc3_rec709"
        case .bmFilmGen5Rec709: resourceName = "bm_film_gen5_rec709"
        case .redIPP2Rec709:    resourceName = "red_ipp2_rec709"
        case .none, .customCube: return nil
        }

        // Search known, deterministic bundles first.
        let searchBundles: [Bundle] = [Bundle(for: LUTManagerClass.self), Bundle.main]
        if let bundled = searchBundles.lazy.compactMap({
            $0.url(forResource: resourceName, withExtension: "cube")
                ?? $0.url(forResource: resourceName, withExtension: "cube", subdirectory: "LUTs")
                ?? $0.url(forResource: resourceName, withExtension: "cube", subdirectory: "Resources/LUTs")
        }).first {
            return bundled
        }

        // SwiftPM package tests may not embed the LUT folder as a bundle resource
        // when the resources live outside the target directory; allow a source-tree
        // fallback so local/dev test runs can still validate LUT parsing.
        let sourceTreeCandidates = [
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../../Resources/LUTs/\(resourceName).cube")
                .standardizedFileURL
        ]
        return sourceTreeCandidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    /// Parametric Rec.709 approximation used when the .cube file is absent.
    /// Good enough for monitoring; replaced by the real LUT once files ship.
    private static func parametricRec709Approximation(for lut: ProxyLUT, input: CIImage) -> CIImage {
        // Each log format has a different "gamma lift" to get to Rec.709-ish appearance.
        let gamma: Float
        switch lut {
        case .arriLogC3Rec709:  gamma = 1.0 / 2.2   // LogC3 is relatively mild
        case .bmFilmGen5Rec709: gamma = 1.0 / 2.6   // BM Film Gen 5 is very flat
        case .redIPP2Rec709:    gamma = 1.0 / 2.4   // IPP2 mid-point
        case .none, .customCube: gamma = 1.0
        }
        return input.applyingFilter("CIGammaAdjust", parameters: [
            "inputPower": gamma
        ])
    }

    /// Parses a .cube file and returns (flatRGBAData, cubeDimension) suitable for CIColorCube.
    private static func parseCUBEData(_ data: Data) -> (Data, Int)? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var dimension = 33
        var floats: [Float] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let d = Int(parts[1]) { dimension = d }
                continue
            }
            if trimmed.hasPrefix("TITLE") || trimmed.hasPrefix("DOMAIN") { continue }
            let parts = trimmed.split(separator: " ")
            if parts.count >= 3,
               let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                floats.append(r); floats.append(g); floats.append(b); floats.append(1.0)
            }
        }

        let expectedCount = dimension * dimension * dimension * 4
        guard !floats.isEmpty, floats.count == expectedCount else { return nil }
        let rawData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        return (rawData, dimension)
    }

    /// Wraps a CVPixelBuffer back into a CMSampleBuffer, copying timing from `source`.
    public static func sampleBuffer(
        wrapping pixelBuffer: CVPixelBuffer,
        timingFrom source: CMSampleBuffer
    ) -> CMSampleBuffer? {
        rebuildSampleBuffer(from: pixelBuffer, timing: source)
    }

    /// Wraps a CVPixelBuffer back into a CMSampleBuffer, copying timing from `source`.
    private static func rebuildSampleBuffer(
        from pixelBuffer: CVPixelBuffer,
        timing source: CMSampleBuffer
    ) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(source, at: 0, timingInfoOut: &timingInfo) == noErr else {
            return nil
        }
        var formatDesc: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: pixelBuffer,
                                                     formatDescriptionOut: &formatDesc)
        guard let desc = formatDesc else { return nil }
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        guard status == noErr else { return nil }
        return newBuffer
    }
    
    private static func createPixelBuffer(from original: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(original)
        let height = CVPixelBufferGetHeight(original)
        let pixelFormatType = CVPixelBufferGetPixelFormatType(original)
        
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormatType,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        if let planeCount = CVPixelBufferGetPlaneCount(original) as Int?, planeCount > 1 {
            // For planar formats (like 420v/420f)
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                pixelFormatType,
                attributes as CFDictionary,
                &pixelBuffer
            )
            return pixelBuffer
        } else {
            // For interleaved formats
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                pixelFormatType,
                attributes as CFDictionary,
                &pixelBuffer
            )
            return pixelBuffer
        }
    }
}

// Bundle anchor — gives Bundle(for:) a class to find the ingest daemon's bundle.
private final class LUTManagerClass: NSObject {}

// MARK: - Custom LUT Support

public struct CustomLUT {
    public let name: String
    public let data: Data
    public let inputColorSpace: String
    public let outputColorSpace: String
    
    public init(name: String, data: Data, inputColorSpace: String, outputColorSpace: String) {
        self.name = name
        self.data = data
        self.inputColorSpace = inputColorSpace
        self.outputColorSpace = outputColorSpace
    }
}

public extension LUTManager {
    static func loadCustomLUTs() -> [CustomLUT] {
        var luts: [CustomLUT] = []
        
        // Built-in LUTs directory
        let lutsDirectory = Bundle.main.bundleURL.appendingPathComponent("Resources/LUTs")
        
        // User LUTs directory
        let userLutsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SLATE/LUTs")
        
        let directories = [lutsDirectory, userLutsDirectory].compactMap { $0 }
        
        for directory in directories {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            
            do {
                let lutFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                
                for fileURL in lutFiles where fileURL.pathExtension.lowercased() == "cube" {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let lut = parseCUBELUT(data: data, filename: fileURL.lastPathComponent)
                        luts.append(lut)
                    } catch {
                        print("Failed to load LUT from \(fileURL.lastPathComponent): \(error)")
                    }
                }
            } catch {
                print("Failed to enumerate LUTs in \(directory): \(error)")
            }
        }
        
        return luts
    }
    
    private static func parseCUBELUT(data: Data, filename: String) -> CustomLUT {
        // Simple .cube LUT parser
        let string = String(data: data, encoding: .utf8) ?? ""
        let lines = string.components(separatedBy: .newlines)
        
        var title = filename
        var inputColorSpace = "Rec.709"
        var outputColorSpace = "Rec.709"
        
        for line in lines {
            if line.hasPrefix("TITLE ") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.contains("INPUT_COLOR_SPACE") {
                inputColorSpace = extractValue(from: line)
            } else if line.contains("OUTPUT_COLOR_SPACE") {
                outputColorSpace = extractValue(from: line)
            }
        }
        
        return CustomLUT(
            name: title,
            data: data,
            inputColorSpace: inputColorSpace,
            outputColorSpace: outputColorSpace
        )
    }
    
    private static func extractValue(from line: String) -> String {
        let components = line.components(separatedBy: " ")
        return components.last ?? ""
    }
}
