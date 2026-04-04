import AVFoundation
import Foundation
import SLATESharedTypes

public struct CameraMetadataExtractor {
    public static func extract(from url: URL) -> CameraMetadata? {
        guard let asset = AVAsset(url: url) else { return nil }
        
        var metadata = CameraMetadata()
        
        // Extract from common metadata
        if let commonMetadata = asset.commonMetadata {
            for item in commonMetadata {
                guard let key = item.commonKey?.rawValue else { continue }
                
                switch key {
                case AVMetadataCommonKeyModel:
                    metadata.cameraModel = item.stringValue
                case AVMetadataCommonKeySoftware:
                    metadata.recordingFormat = item.stringValue
                case AVMetadataCommonKeyCreationDate:
                    if let dateValue = item.dateValue {
                        metadata.recordingDate = ISO8601DateFormatter().string(from: dateValue)
                    }
                default:
                    break
                }
            }
        }
        
        // Extract from format-specific metadata
        extractFormatSpecificMetadata(from: asset, metadata: &metadata)
        
        // Extract technical details
        extractTechnicalDetails(from: asset, metadata: &metadata)
        
        return metadata
    }
    
    private static func extractFormatSpecificMetadata(from asset: AVAsset, metadata: inout CameraMetadata) {
        // Try to get format description from the first video track
        guard let videoTrack = asset.tracks(withMediaType: .video).first,
              let formatDesc = videoTrack.formatDescriptions.first else { return }
        
        let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
        guard mediaType == kCMMediaType_Video else { return }
        
        // Extract codec details
        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
        metadata.codec = fourCCToString(codecType)
        
        // Extract dimensions
        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
        metadata.width = Int(dimensions.width)
        metadata.height = Int(dimensions.height)
        
        // Extract frame rate
        if let frameRate = videoTrack.nominalFrameRate as Double? {
            metadata.frameRate = frameRate
        }
        
        // Extract color space
        if let extensions = CMFormatDescriptionGetExtensions(formatDesc) as Dictionary? {
            if let colorPrimaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String {
                metadata.colorSpace = colorPrimaries
            }
        }
    }
    
    private static func extractTechnicalDetails(from asset: AVAsset, metadata: inout CameraMetadata) {
        // Extract duration
        let duration = asset.duration
        metadata.duration = CMTimeGetSeconds(duration)
        
        // Extract bit rate if available
        if let estimatedDuration = asset.estimatedDuration,
           let fileSize = try? FileManager.default.attributesOfItem(atPath: asset.url.path)[.size] as? Int64 {
            metadata.bitrate = Int64(Double(fileSize * 8) / CMTimeGetSeconds(estimatedDuration))
        }
        
        // Extract lens metadata if available
        extractLensMetadata(from: asset, metadata: &metadata)
    }
    
    private static func extractLensMetadata(from asset: AVAsset, metadata: inout CameraMetadata) {
        // Look for lens metadata in available metadata
        for track in asset.tracks {
            for item in track.formatDescriptions {
                let extensions = CMFormatDescriptionGetExtensions(item) as Dictionary?
                
                // Look for lens-specific metadata
                if let extensions = extensions {
                    if let focalLength = extensions[kCMFormatDescriptionExtension_FocalLength] as? NSNumber {
                        metadata.focalLength = focalLength.doubleValue
                    }
                    if let aperture = extensions[kCMFormatDescriptionExtension_Aperture] as? NSNumber {
                        metadata.aperture = aperture.doubleValue
                    }
                    if let iso = extensions[kCMFormatDescriptionExtension_ISO] as? NSNumber {
                        metadata.iso = iso.intValue
                    }
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
