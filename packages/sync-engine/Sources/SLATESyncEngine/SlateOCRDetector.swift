import AVFoundation
import Foundation
import Vision

enum SlateOCRDetector {
    static func detectVideoStartTimecode(
        in videoURL: URL,
        fps: Double,
        maxSearchSeconds: Double = 5
    ) async throws -> SlateOCRDetection? {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let sampleLimit = min(max(duration, 0), maxSearchSeconds)
        guard sampleLimit > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 900)

        var detections: [SlateOCRDetection] = []
        for sample in stride(from: 0.0, through: sampleLimit, by: 0.25) {
            var actualTime = CMTime.zero
            let cgImage = try generator.copyCGImage(at: CMTime(seconds: sample, preferredTimescale: 600), actualTime: &actualTime)
            let observedAt = actualTime.seconds

            for candidate in try recognizeTimecodes(in: cgImage, fps: fps) {
                let clipStart = candidate.displayedSeconds - observedAt
                guard clipStart >= -(1 / max(fps, 1)), clipStart <= 86_400 else { continue }
                detections.append(
                    SlateOCRDetection(
                        clipStartSeconds: clipStart,
                        observedAtSeconds: observedAt,
                        confidence: candidate.confidence,
                        rawText: candidate.rawText
                    )
                )
            }
        }

        guard !detections.isEmpty else { return nil }

        let grouped = Dictionary(grouping: detections) { detection in
            Int((detection.clipStartSeconds * fps).rounded())
        }

        guard let bestGroup = grouped.max(by: { groupConfidence($0.value) < groupConfidence($1.value) })?.value else {
            return nil
        }

        let averageStart = bestGroup.reduce(0.0) { $0 + $1.clipStartSeconds } / Double(bestGroup.count)
        let averageObservedAt = bestGroup.reduce(0.0) { $0 + $1.observedAtSeconds } / Double(bestGroup.count)
        let averageConfidence = groupConfidence(bestGroup) / Float(bestGroup.count)

        return SlateOCRDetection(
            clipStartSeconds: averageStart,
            observedAtSeconds: averageObservedAt,
            confidence: averageConfidence,
            rawText: bestGroup.max(by: { $0.confidence < $1.confidence })?.rawText ?? ""
        )
    }

    private static func recognizeTimecodes(
        in image: CGImage,
        fps: Double
    ) throws -> [(displayedSeconds: Double, confidence: Float, rawText: String)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.04

        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        var rawCandidates: [(text: String, confidence: Float)] = []
        for observation in observations {
            for candidate in observation.topCandidates(2) {
                rawCandidates.append((candidate.string, candidate.confidence))
            }
        }

        if !rawCandidates.isEmpty {
            let merged = rawCandidates.map(\.text).joined(separator: " ")
            let mergedConfidence = rawCandidates.reduce(Float.zero) { $0 + $1.confidence } / Float(rawCandidates.count)
            rawCandidates.append((merged, mergedConfidence))
        }

        var parsed: [(displayedSeconds: Double, confidence: Float, rawText: String)] = []
        for candidate in rawCandidates {
            for token in extractTimecodeCandidates(from: candidate.text, fps: fps) {
                if let seconds = TimecodeMetadata.parseTimecode(token, fps: fps) {
                    parsed.append((seconds, candidate.confidence, token))
                }
            }
        }

        return parsed
    }

    private static func extractTimecodeCandidates(from raw: String, fps: Double) -> [String] {
        let normalized = normalizeOCRText(raw)
        let pattern = #"[0-9]{2}[:;\.\s-]?[0-9]{2}[:;\.\s-]?[0-9]{2}[:;\.\s-]?[0-9]{2}"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = regex?.matches(in: normalized, range: range) ?? []

        var tokens: [String] = []
        for match in matches {
            guard let substringRange = Range(match.range, in: normalized) else { continue }
            let rawToken = String(normalized[substringRange])
            if let candidate = canonicalizeTimecodeToken(rawToken, fps: fps) {
                tokens.append(candidate)
            }
        }

        if tokens.isEmpty, let candidate = canonicalizeTimecodeToken(normalized, fps: fps) {
            tokens.append(candidate)
        }

        return Array(Set(tokens))
    }

    private static func canonicalizeTimecodeToken(_ raw: String, fps: Double) -> String? {
        let keepers = raw.filter { $0.isNumber || [":", ";", ".", " ", "-"].contains($0) }
        let digits = keepers.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }

        let slice = String(digits.prefix(8))
        let groups = stride(from: 0, to: slice.count, by: 2).map { index -> String in
            let start = slice.index(slice.startIndex, offsetBy: index)
            let end = slice.index(start, offsetBy: 2)
            return String(slice[start..<end])
        }

        guard groups.count == 4 else { return nil }
        let frameSeparator = (raw.contains(";") || raw.contains(".")) && fps >= 29 ? ";" : ":"
        return "\(groups[0]):\(groups[1]):\(groups[2])\(frameSeparator)\(groups[3])"
    }

    private static func normalizeOCRText(_ raw: String) -> String {
        raw.uppercased()
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "Q", with: "0")
            .replacingOccurrences(of: "D", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .replacingOccurrences(of: "|", with: "1")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "B", with: "8")
            .replacingOccurrences(of: "Z", with: "2")
    }

    private static func groupConfidence(_ detections: [SlateOCRDetection]) -> Float {
        detections.reduce(Float.zero) { $0 + $1.confidence }
    }
}
