import Foundation
import SLATESharedTypes

public extension SyncConfidence {
    var rank: Int {
        switch self {
        case .high: 4
        case .medium: 3
        case .low: 2
        case .manualRequired: 1
        case .unsynced: 0
        }
    }
}

public struct SyncConfiguration: Sendable {
    public let clapSearchSeconds: Double
    public let clapPreRollSeconds: Double
    public let clapSampleRate: Double
    public let coarseCorrelationRate: Double
    public let fineCorrelationRate: Double
    public let searchWindowSeconds: Double
    public let highConfidenceThreshold: Float
    public let mediumConfidenceThreshold: Float

    public init(
        clapSearchSeconds: Double = 10,
        clapPreRollSeconds: Double = 2,
        clapSampleRate: Double = 2_000,
        coarseCorrelationRate: Double = 60,
        fineCorrelationRate: Double = 1_000,
        searchWindowSeconds: Double = 30,
        highConfidenceThreshold: Float = 0.72,
        mediumConfidenceThreshold: Float = 0.45
    ) {
        self.clapSearchSeconds = clapSearchSeconds
        self.clapPreRollSeconds = clapPreRollSeconds
        self.clapSampleRate = clapSampleRate
        self.coarseCorrelationRate = coarseCorrelationRate
        self.fineCorrelationRate = fineCorrelationRate
        self.searchWindowSeconds = searchWindowSeconds
        self.highConfidenceThreshold = highConfidenceThreshold
        self.mediumConfidenceThreshold = mediumConfidenceThreshold
    }
}

struct LoadedAudio: Sendable {
    let samples: [Float]
    let sampleRate: Double
    let channels: Int
    let duration: Double
}

struct TimecodeInfo: Codable, Sendable {
    let startSeconds: Double
}

struct SlateOCRDetection: Sendable {
    let clipStartSeconds: Double
    let observedAtSeconds: Double
    let confidence: Float
    let rawText: String
}

// MARK: - Multi-Camera Sync Models

public struct CameraOffset: Codable, Sendable {
    public let cameraURL: URL
    public let offsetFrames: Int           // positive = this camera is ahead of primary
    public let offsetSeconds: Double
    public let confidence: SyncConfidence  // reuse existing enum
    public let method: MultiCamSyncMethod  // how we determined the offset

    public init(
        cameraURL: URL,
        offsetFrames: Int,
        offsetSeconds: Double,
        confidence: SyncConfidence,
        method: MultiCamSyncMethod
    ) {
        self.cameraURL = cameraURL
        self.offsetFrames = offsetFrames
        self.offsetSeconds = offsetSeconds
        self.confidence = confidence
        self.method = method
    }
}

public enum MultiCamSyncMethod: String, Codable, Sendable {
    case timecodeMetadata    // LTC/VITC from file metadata
    case slateDetection      // visual slate frame matching
    case audioCorrelation    // waveform cross-correlation (fallback)
    case manual              // could not determine, needs manual sync
}

public struct MultiCamSyncResult: Codable, Sendable {
    public let primaryCamera: URL
    public let offsets: [CameraOffset]     // one per additionalCamera
    public let overallConfidence: SyncConfidence
    public let notes: [String]             // human-readable notes about sync decisions

    public init(
        primaryCamera: URL,
        offsets: [CameraOffset],
        overallConfidence: SyncConfidence,
        notes: [String]
    ) {
        self.primaryCamera = primaryCamera
        self.offsets = offsets
        self.overallConfidence = overallConfidence
        self.notes = notes
    }
}

// MARK: - Camera Group Sync API (v1.2)
// Higher-level typed API over syncMultiCam for grouped multi-angle ingest.
// CameraInput ties a source URL to a camera angle letter (A/B/C/D).
// CameraGroupSyncResult mirrors data-model.json cameraGroupSyncResult.

public enum CameraAngle: String, Codable, Sendable, CaseIterable {
    case A, B, C, D
}

public struct CameraInput: Sendable {
    public let url: URL
    public let angle: CameraAngle
    /// Optional — the clip's DB identifier, written into CameraGroupOffset
    public let clipId: String?

    public init(url: URL, angle: CameraAngle, clipId: String? = nil) {
        self.url = url
        self.angle = angle
        self.clipId = clipId
    }
}

/// Per-angle offset relative to the primary (angle A).
public struct CameraGroupOffset: Codable, Sendable {
    public let angle: CameraAngle
    public let clipId: String?
    public let offsetFrames: Int
    public let offsetSeconds: Double
    public let confidence: SyncConfidence
    public let method: MultiCamSyncMethod

    public init(
        angle: CameraAngle,
        clipId: String?,
        offsetFrames: Int,
        offsetSeconds: Double,
        confidence: SyncConfidence,
        method: MultiCamSyncMethod
    ) {
        self.angle = angle
        self.clipId = clipId
        self.offsetFrames = offsetFrames
        self.offsetSeconds = offsetSeconds
        self.confidence = confidence
        self.method = method
    }
}

/// Result of syncing an entire camera group against a shared primary (angle A).
public struct CameraGroupSyncResult: Codable, Sendable {
    public let groupId: String
    public let primaryAngle: CameraAngle
    public let offsets: [CameraGroupOffset]   // one per non-primary angle
    public let overallConfidence: SyncConfidence
    public let syncedAt: String               // ISO 8601

    public init(
        groupId: String,
        primaryAngle: CameraAngle = .A,
        offsets: [CameraGroupOffset],
        overallConfidence: SyncConfidence,
        syncedAt: String
    ) {
        self.groupId = groupId
        self.primaryAngle = primaryAngle
        self.offsets = offsets
        self.overallConfidence = overallConfidence
        self.syncedAt = syncedAt
    }
}
