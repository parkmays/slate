import AVFoundation
import CoreGraphics
import Foundation
import Vision

public struct FaceCluster: Codable, Sendable {
    public let clusterKey: String
    public let representativeFrameSeconds: Double
    public let averageBoundingBox: CGRect

    public init(clusterKey: String, representativeFrameSeconds: Double, averageBoundingBox: CGRect) {
        self.clusterKey = clusterKey
        self.representativeFrameSeconds = representativeFrameSeconds
        self.averageBoundingBox = averageBoundingBox
    }
}

public struct FaceClusterService {
    public init() {}

    /// Detect face observations and group them into coarse clusters by normalized position and scale.
    public func clusterFaces(proxyURL: URL, sampleFPS: Double = 1.0) async throws -> [FaceCluster] {
        let asset = AVURLAsset(url: proxyURL)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        let step = max(1.0 / max(sampleFPS, 0.5), 0.25)
        let times = stride(from: 0.0, to: duration, by: step).map { CMTime(seconds: $0, preferredTimescale: 600) }

        struct Bucket {
            var count: Int
            var frameSum: Double
            var xSum: CGFloat
            var ySum: CGFloat
            var wSum: CGFloat
            var hSum: CGFloat
        }

        var buckets: [String: Bucket] = [:]
        for time in times {
            let cgImage = try await generator.image(at: time).image
            let observations = try detectFaces(in: cgImage)
            for observation in observations {
                let box = observation.boundingBox
                let key = bucketKey(for: box)
                var bucket = buckets[key] ?? Bucket(count: 0, frameSum: 0, xSum: 0, ySum: 0, wSum: 0, hSum: 0)
                bucket.count += 1
                bucket.frameSum += time.seconds
                bucket.xSum += box.origin.x
                bucket.ySum += box.origin.y
                bucket.wSum += box.width
                bucket.hSum += box.height
                buckets[key] = bucket
            }
        }

        return buckets.map { key, bucket in
            let divisor = CGFloat(max(bucket.count, 1))
            return FaceCluster(
                clusterKey: key,
                representativeFrameSeconds: bucket.frameSum / Double(max(bucket.count, 1)),
                averageBoundingBox: CGRect(
                    x: bucket.xSum / divisor,
                    y: bucket.ySum / divisor,
                    width: bucket.wSum / divisor,
                    height: bucket.hSum / divisor
                )
            )
        }
        .sorted { $0.clusterKey < $1.clusterKey }
    }

    private func detectFaces(in image: CGImage) throws -> [VNFaceObservation] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    private func bucketKey(for box: CGRect) -> String {
        let x = Int((box.midX * 4).rounded())
        let y = Int((box.midY * 4).rounded())
        let area = Int((box.width * box.height * 8).rounded())
        return "face-\(x)-\(y)-\(max(1, area))"
    }
}
