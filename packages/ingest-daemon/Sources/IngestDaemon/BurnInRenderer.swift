// SLATE — Proxy burn-in (timecode + metadata) via Core Image only.

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Metal
import SLATESharedTypes

/// Renders optional text overlays onto proxy frames for on-set / editorial identification.
public struct BurnInRenderer: Sendable {
    public init() {}

    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext(options: [.useSoftwareRenderer: true])
    }()

    /// Advances `startTC` by `frameNumber` frames at `fps`, returning `HH:MM:SS:FF`.
    public func timecodeString(startTC: String, frameNumber: Int, fps: Double) -> String {
        let fpsInt = Self.effectiveTimecodeFPS(fps)
        let startFrames = Self.parseTimecodeToTotalFrames(startTC, fps: fpsInt) ?? 0
        let total = max(0, startFrames + frameNumber)
        return Self.encodeFrames(total, fps: fpsInt)
    }

    /// Composites timecode + metadata over `pixelBuffer`. Returns `nil` on any failure (caller keeps the original frame).
    public func renderBurnIn(
        pixelBuffer: CVPixelBuffer,
        timecodeString: String,
        metadataLine: String,
        config: BurnInConfig,
        outputWidth: Int,
        outputHeight: Int
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width == outputWidth, height == outputHeight else { return nil }

        let videoImage = CIImage(cvPixelBuffer: pixelBuffer)
        let videoExtent = videoImage.extent
        guard videoExtent.width > 1, videoExtent.height > 1 else { return nil }

        let line1 = "TC: \(timecodeString)"
        let line2 = metadataLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText: String
        if line2.isEmpty {
            fullText = line1
        } else {
            fullText = line1 + "\n" + line2
        }

        guard let textImage = Self.makeTextImage(
            text: fullText,
            fontSize: CGFloat(config.fontSize),
            textColor: config
        ) else {
            return nil
        }

        let padding: CGFloat = 10
        let bgRect = textImage.extent.insetBy(dx: -padding, dy: -padding)
        guard let bgImage = Self.solidColorImage(
            red: CGFloat(config.backgroundColorRed),
            green: CGFloat(config.backgroundColorGreen),
            blue: CGFloat(config.backgroundColorBlue),
            alpha: CGFloat(config.backgroundColorAlpha),
            extent: bgRect
        ) else {
            return nil
        }

        let textCentered = Self.center(textImage, in: bgRect)
        let labelGroup = textCentered.composited(over: bgImage)

        let margin: CGFloat = 16
        let txTy = Self.translation(
            for: config.position,
            groupExtent: labelGroup.extent,
            videoExtent: videoExtent,
            margin: margin
        )
        let placed = labelGroup.transformed(by: CGAffineTransform(translationX: txTy.x, y: txTy.y))
        guard let overVideo = Self.sourceOver(foreground: placed, background: videoImage) else {
            return nil
        }

        guard let out = Self.makeOutputPixelBuffer(matching: pixelBuffer) else { return nil }
        guard let cs = CGColorSpace(name: CGColorSpace.itur_709) else { return nil }
        Self.ciContext.render(overVideo, to: out, bounds: videoExtent, colorSpace: cs)
        return out
    }

    // MARK: - Timecode math

    private static func effectiveTimecodeFPS(_ fps: Double) -> Int {
        if fps < 0.000_1 { return 24 }
        if abs(fps - 24_000.0 / 1001.0) < 0.02 { return 24 }
        if abs(fps - 30_000.0 / 1001.0) < 0.02 { return 30 }
        if abs(fps - 23.976) < 0.02 { return 24 }
        if abs(fps - 29.97) < 0.02 { return 30 }
        let rounded = Int(round(fps))
        let clamped = max(1, min(120, rounded))
        if [24, 25, 30, 48, 60].contains(clamped) { return clamped }
        return clamped
    }

    private static func parseTimecodeToTotalFrames(_ raw: String, fps: Int) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sep: Character = trimmed.contains(";") ? ";" : ":"
        let parts = trimmed.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }

        let h = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
        let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        let s = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
        let f = Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 0
        let fpsClamped = max(1, fps)
        return ((h * 60 + m) * 60 + s) * fpsClamped + f
    }

    private static func encodeFrames(_ total: Int, fps: Int) -> String {
        let fpsClamped = max(1, fps)
        var frames = total % fpsClamped
        var t = total / fpsClamped
        if frames < 0 { frames += fpsClamped; t -= 1 }

        let sec = t % 60
        t /= 60
        let min = t % 60
        let hour = t / 60

        return String(format: "%02d:%02d:%02d:%02d", hour, min, sec, frames)
    }

    // MARK: - Core Image helpers

    private static func makeTextImage(text: String, fontSize: CGFloat, textColor: BurnInConfig) -> CIImage? {
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, fontSize, nil)
        let cgColor = CGColor(
            red: CGFloat(textColor.textColorRed),
            green: CGFloat(textColor.textColorGreen),
            blue: CGFloat(textColor.textColorBlue),
            alpha: CGFloat(textColor.textColorAlpha)
        )
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): cgColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attr)

        guard let filter = CIFilter(name: "CIAttributedTextImageGenerator") else { return nil }
        filter.setValue(attributed, forKey: "inputAttributedText")
        filter.setValue(1.0, forKey: "inputScaleFactor")
        return filter.outputImage
    }

    private static func solidColorImage(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat, extent: CGRect) -> CIImage? {
        let color = CIColor(red: red, green: green, blue: blue, alpha: alpha)
        let img = CIImage(color: color).cropped(to: extent)
        return img
    }

    private static func center(_ text: CIImage, in rect: CGRect) -> CIImage {
        let te = text.extent
        let dx = rect.midX - te.midX
        let dy = rect.midY - te.midY
        return text.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    /// Positions overlay in Core Image coordinates (origin bottom-left; `videoExtent` is the frame bounds).
    private static func translation(
        for position: BurnInPosition,
        groupExtent: CGRect,
        videoExtent: CGRect,
        margin: CGFloat
    ) -> CGPoint {
        let gw = groupExtent.width
        let vh = videoExtent.height
        let vw = videoExtent.width
        let vx = videoExtent.minX
        let vy = videoExtent.minY

        switch position {
        case .bottomLeft:
            let tx = vx + margin - groupExtent.minX
            let ty = vy + margin - groupExtent.minY
            return CGPoint(x: tx, y: ty)
        case .bottomCenter:
            let tx = vx + (vw - gw) / 2 - groupExtent.minX
            let ty = vy + margin - groupExtent.minY
            return CGPoint(x: tx, y: ty)
        case .topLeft:
            let tx = vx + margin - groupExtent.minX
            let ty = vy + vh - margin - groupExtent.maxY
            return CGPoint(x: tx, y: ty)
        case .topCenter:
            let tx = vx + (vw - gw) / 2 - groupExtent.minX
            let ty = vy + vh - margin - groupExtent.maxY
            return CGPoint(x: tx, y: ty)
        }
    }

    private static func sourceOver(foreground: CIImage, background: CIImage) -> CIImage? {
        guard let f = CIFilter(name: "CISourceOverCompositing") else { return nil }
        f.setValue(foreground, forKey: kCIInputImageKey)
        f.setValue(background, forKey: kCIInputBackgroundImageKey)
        return f.outputImage
    }

    private static func makeOutputPixelBuffer(matching original: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(original)
        let height = CVPixelBufferGetHeight(original)
        let pixelFormat = CVPixelBufferGetPixelFormatType(original)

        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var out: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &out
        )
        guard status == kCVReturnSuccess, let buffer = out else { return nil }
        return buffer
    }
}
