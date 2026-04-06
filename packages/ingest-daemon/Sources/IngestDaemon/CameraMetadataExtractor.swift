import AVFoundation
import CoreMedia
import Foundation
import SLATESharedTypes

public struct CameraMetadataExtractor {
    public static func extract(from url: URL) async -> CameraMetadata? {
        let asset = AVURLAsset(url: url)

        var metadata = CameraMetadata()

        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata {
                guard let key = item.commonKey?.rawValue else { continue }

                switch key {
                case AVMetadataKey.commonKeyModel.rawValue:
                    if let s = try? await item.load(.stringValue) {
                        metadata.cameraModel = s
                    }
                case AVMetadataKey.commonKeySoftware.rawValue:
                    if let s = try? await item.load(.stringValue) {
                        metadata.recordingFormat = s
                    }
                case AVMetadataKey.commonKeyCreationDate.rawValue:
                    if let d = try? await item.load(.dateValue) {
                        metadata.recordingDate = ISO8601DateFormatter().string(from: d)
                    }
                default:
                    break
                }
            }
        }

        await extractFormatSpecificMetadata(from: asset, metadata: &metadata)
        await extractTechnicalDetails(from: url, asset: asset, metadata: &metadata)

        return metadata
    }

    private static func extractFormatSpecificMetadata(from asset: AVURLAsset, metadata: inout CameraMetadata) async {
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard let videoTrack = videoTracks.first else { return }
        let formatDescriptions = (try? await videoTrack.load(.formatDescriptions)) ?? []
        guard let formatDesc = formatDescriptions.first else { return }

        let desc = formatDesc as CMFormatDescription

        let mediaType = CMFormatDescriptionGetMediaType(desc)
        guard mediaType == kCMMediaType_Video else { return }

        let codecType = CMFormatDescriptionGetMediaSubType(desc)
        metadata.codec = fourCCToString(codecType)

        let dimensions = CMVideoFormatDescriptionGetDimensions(desc as CMVideoFormatDescription)
        metadata.width = Int(dimensions.width)
        metadata.height = Int(dimensions.height)

        if let frameRate = try? await videoTrack.load(.nominalFrameRate), frameRate > 0 {
            metadata.frameRate = Double(frameRate)
        }

        if let ex = CMFormatDescriptionGetExtensions(desc) as NSDictionary? as? [String: Any],
           let colorPrimaries = ex[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String {
            metadata.colorSpace = colorPrimaries
        }
    }

    private static func extractTechnicalDetails(from url: URL, asset: AVURLAsset, metadata: inout CameraMetadata) async {
        guard let duration = try? await asset.load(.duration) else { return }
        metadata.duration = CMTimeGetSeconds(duration)

        if CMTimeGetSeconds(duration) > 0,
           let fileSize = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
            metadata.bitrate = Int64(Double(fileSize * 8) / CMTimeGetSeconds(duration))
        }

        await extractLensMetadata(from: asset, metadata: &metadata)
    }

    private static func extractLensMetadata(from asset: AVURLAsset, metadata: inout CameraMetadata) async {
        let tracks = (try? await asset.load(.tracks)) ?? []
        for track in tracks {
            let formats = (try? await track.load(.formatDescriptions)) ?? []
            for formatDesc in formats {
                let desc = formatDesc as CMFormatDescription
                guard let ex = CMFormatDescriptionGetExtensions(desc) else { continue }
                let nsDict = ex as NSDictionary
                // Keys are CFString constants; bridge via NSDictionary subscript.
                if let focal = nsDict["FocalLength" as NSString] as? NSNumber {
                    metadata.focalLength = focal.doubleValue
                }
                if let aperture = nsDict["Aperture" as NSString] as? NSNumber {
                    metadata.aperture = aperture.doubleValue
                }
                if let iso = nsDict["ISO" as NSString] as? NSNumber {
                    metadata.iso = iso.intValue
                }
            }
        }
    }

    private static func fourCCToString(_ fourCC: FourCharCode) -> String {
        let bytes = [
            UInt8((fourCC >> 24) & 0xFF),
            UInt8((fourCC >> 16) & 0xFF),
            UInt8((fourCC >> 8) & 0xFF),
            UInt8(fourCC & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
