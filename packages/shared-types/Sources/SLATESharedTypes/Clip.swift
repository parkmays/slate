// SLATE — Canonical Clip data model (Swift)
// Source of truth: contracts/data-model.json (version 1.0)
// Author: Claude Code (Orchestrator)
//
// Mirrors packages/shared-types/src/clip.ts exactly.
// All agents consume these types. Do not modify without bumping
// data-model.json version and notifying all agents.
//
// Requires: macOS 14+, Swift 5.9+

import Foundation

// MARK: - Enumerations

public enum SourceFormat: String, Codable, Sendable, CaseIterable {
    case braw       = "BRAW"
    case arriraw    = "ARRIRAW"
    case proRes422HQ = "ProRes422HQ"
    case h264       = "H264"
    case mxf        = "MXF"
    case r3d        = "R3D"
}

public enum ProxyStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case processing
    case ready
    case uploading
    case completed
    case error
}

public enum AIProcessingStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case processing
    case ready
    case error
}

public enum ReviewStatus: String, Codable, Sendable, CaseIterable {
    case unreviewed
    case circled
    case flagged
    case x
    case deprioritized
}

public enum ApprovalStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case reviewed
    case approved
}

public enum ProjectMode: String, Codable, Sendable, CaseIterable {
    case narrative
    case documentary
}

public enum SyncConfidence: String, Codable, Sendable, CaseIterable {
    case high
    case medium
    case low
    case manualRequired = "manual_required"
    case unsynced
}

public enum SyncMethod: String, Codable, Sendable, CaseIterable {
    case waveformCorrelation = "waveform_correlation"
    case timecode
    case manual
    case none
}

public enum AudioTrackRole: String, Codable, Sendable, CaseIterable {
    case boom
    case lav
    case mix
    case iso
    case unknown
}

public enum AnnotationType: String, Codable, Sendable, CaseIterable {
    case text
    case voice
}

public enum ScoreFlag: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case error
}

public enum AssemblyClipRole: String, Codable, Sendable, CaseIterable {
    case primary
    case broll
    case interview
}

// MARK: - Supporting types

public struct NarrativeMeta: Codable, Sendable, Equatable {
    public var sceneNumber: String
    public var shotCode: String
    public var takeNumber: Int
    public var cameraId: String
    public var scriptPage: String?
    public var setUpDescription: String?
    public var director: String?
    public var dp: String?

    public init(
        sceneNumber: String,
        shotCode: String,
        takeNumber: Int,
        cameraId: String,
        scriptPage: String? = nil,
        setUpDescription: String? = nil,
        director: String? = nil,
        dp: String? = nil
    ) {
        self.sceneNumber = sceneNumber
        self.shotCode = shotCode
        self.takeNumber = takeNumber
        self.cameraId = cameraId
        self.scriptPage = scriptPage
        self.setUpDescription = setUpDescription
        self.director = director
        self.dp = dp
    }
}

public struct DocumentaryMeta: Codable, Sendable, Equatable {
    public var subjectName: String
    /// UUID
    public var subjectId: String
    public var shootingDay: Int
    public var sessionLabel: String
    public var location: String?
    public var topicTags: [String]
    public var interviewerOffscreen: Bool

    public init(
        subjectName: String,
        subjectId: String,
        shootingDay: Int,
        sessionLabel: String,
        location: String? = nil,
        topicTags: [String] = [],
        interviewerOffscreen: Bool = false
    ) {
        self.subjectName = subjectName
        self.subjectId = subjectId
        self.shootingDay = shootingDay
        self.sessionLabel = sessionLabel
        self.location = location
        self.topicTags = topicTags
        self.interviewerOffscreen = interviewerOffscreen
    }
}

public struct AudioTrack: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { trackIndex }
    public var trackIndex: Int
    public var role: AudioTrackRole
    public var channelLabel: String
    /// Hz
    public var sampleRate: Double
    public var bitDepth: Int

    public init(
        trackIndex: Int,
        role: AudioTrackRole,
        channelLabel: String,
        sampleRate: Double,
        bitDepth: Int
    ) {
        self.trackIndex = trackIndex
        self.role = role
        self.channelLabel = channelLabel
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
    }
}

public struct SyncResult: Codable, Sendable, Equatable {
    public var confidence: SyncConfidence
    public var method: SyncMethod
    public var offsetFrames: Int
    public var driftPPM: Double
    /// Seconds from start of clip
    public var clapDetectedAt: Double?
    /// ISO 8601
    public var verifiedAt: String?

    public init(
        confidence: SyncConfidence = .unsynced,
        method: SyncMethod = .none,
        offsetFrames: Int = 0,
        driftPPM: Double = 0,
        clapDetectedAt: Double? = nil,
        verifiedAt: String? = nil
    ) {
        self.confidence = confidence
        self.method = method
        self.offsetFrames = offsetFrames
        self.driftPPM = driftPPM
        self.clapDetectedAt = clapDetectedAt
        self.verifiedAt = verifiedAt
    }

    /// Convenience: unsynced default for newly ingested clips
    public static let unsynced = SyncResult()
}

public struct ScoreReason: Codable, Sendable, Equatable {
    public var dimension: String
    /// 0–100
    public var score: Double
    public var flag: ScoreFlag
    public var message: String
    /// HH:MM:SS:FF
    public var timecode: String?

    public init(
        dimension: String,
        score: Double,
        flag: ScoreFlag,
        message: String,
        timecode: String? = nil
    ) {
        self.dimension = dimension
        self.score = score
        self.flag = flag
        self.message = message
        self.timecode = timecode
    }
}

public struct AIScores: Codable, Sendable, Equatable {
    /// Composite 0–100
    public var composite: Double
    public var focus: Double
    public var exposure: Double
    public var stability: Double
    public var audio: Double
    /// Narrative only — nil in documentary mode
    public var performance: Double?
    /// Documentary only — nil in narrative mode
    public var contentDensity: Double?
    /// ISO 8601
    public var scoredAt: String
    public var modelVersion: String
    public var reasoning: [ScoreReason]

    public init(
        composite: Double,
        focus: Double,
        exposure: Double,
        stability: Double,
        audio: Double,
        performance: Double? = nil,
        contentDensity: Double? = nil,
        scoredAt: String,
        modelVersion: String,
        reasoning: [ScoreReason] = []
    ) {
        self.composite = composite
        self.focus = focus
        self.exposure = exposure
        self.stability = stability
        self.audio = audio
        self.performance = performance
        self.contentDensity = contentDensity
        self.scoredAt = scoredAt
        self.modelVersion = modelVersion
        self.reasoning = reasoning
    }
}

public struct Annotation: Codable, Sendable, Equatable, Identifiable {
    /// UUID
    public var id: String
    /// UUID
    public var userId: String
    public var userDisplayName: String
    /// Optional provenance, e.g. `"SoundReport"` for mixer log imports
    public var source: String?
    /// HH:MM:SS:FF
    public var timecodeIn: String
    /// Seconds from clip/proxy start — mirrors web/Postgres `time_offset_seconds` when synced from cloud review.
    public var timeOffsetSeconds: Double?
    /// HH:MM:SS:FF — nil if point annotation
    public var timecodeOut: String?
    public var body: String
    public var type: AnnotationType
    public var voiceUrl: String?
    /// ISO 8601
    public var createdAt: String
    /// ISO 8601
    public var resolvedAt: String?

    public init(
        id: String = UUID().uuidString,
        userId: String,
        userDisplayName: String,
        timecodeIn: String,
        timeOffsetSeconds: Double? = nil,
        timecodeOut: String? = nil,
        body: String,
        type: AnnotationType = .text,
        voiceUrl: String? = nil,
        source: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        resolvedAt: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.source = source
        self.timecodeIn = timecodeIn
        self.timeOffsetSeconds = timeOffsetSeconds
        self.timecodeOut = timecodeOut
        self.body = body
        self.type = type
        self.voiceUrl = voiceUrl
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

// MARK: - Core Clip

/// The universal Clip object. Every agent reads and writes this shape.
/// Original media at `sourcePath` is READ ONLY — never move, rename, or delete it.
public struct Clip: Codable, Sendable, Identifiable {
    /// UUID v4
    public var id: String
    /// UUID — references Project.id
    public var projectId: String
    /// SHA-256 hex (lowercase, 64 chars) of the original file
    public var checksum: String
    /// Absolute path to original — READ ONLY, never mutate
    public var sourcePath: String
    /// Bytes
    public var sourceSize: Int64
    public var sourceFormat: SourceFormat
    /// e.g. 23.976, 24, 25, 29.97, 30, 48, 60
    public var sourceFps: Double
    /// HH:MM:SS:FF (drop-frame uses ';' separator for 29.97)
    public var sourceTimecodeStart: String
    /// Duration in seconds
    public var duration: Double

    public var proxyPath: String?
    public var proxyStatus: ProxyStatus
    /// SHA-256 hex of the proxy file
    public var proxyChecksum: String?
    /// Public R2 (or CDN) URL for the proxy when uploaded — used for digests and cloud review.
    public var proxyR2URL: String?
    /// LUT applied during proxy generation (nil = no LUT / pass-through).
    /// Values: "arri_logc3_rec709" | "bm_film_gen5_rec709" | "red_ipp2_rec709" | "none"
    public var proxyLUT: String?
    /// Color space of the proxy file. Always "rec709" when a LUT was applied.
    public var proxyColorSpace: String?

    /// Populated when projectMode == .narrative, otherwise nil
    public var narrativeMeta: NarrativeMeta?
    /// Populated when projectMode == .documentary, otherwise nil
    public var documentaryMeta: DocumentaryMeta?

    public var audioTracks: [AudioTrack]
    public var syncResult: SyncResult
    public var syncedAudioPath: String?
    /// UUID — links all clips shot simultaneously as a multi-cam group.
    /// All angles in the same setup share this identifier.
    public var cameraGroupId: String?
    /// Camera angle within the group (A/B/C/D). Nil for single-camera clips.
    public var cameraAngle: String?

    /// Provided by Codex ai-pipeline — advisory only, always manually overrideable
    public var aiScores: AIScores?
    /// UUID referencing transcript in Supabase
    public var transcriptId: String?
    public var aiProcessingStatus: AIProcessingStatus

    public var reviewStatus: ReviewStatus
    public var annotations: [Annotation]

    public var approvalStatus: ApprovalStatus
    public var approvedBy: String?
    /// ISO 8601
    public var approvedAt: String?

    /// ISO 8601
    public var ingestedAt: String
    /// ISO 8601
    public var updatedAt: String
    public var projectMode: ProjectMode
    /// Camera and lens metadata extracted from source file
    public var cameraMetadata: CameraMetadata?

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        checksum: String,
        sourcePath: String,
        sourceSize: Int64,
        sourceFormat: SourceFormat,
        sourceFps: Double,
        sourceTimecodeStart: String,
        duration: Double,
        proxyPath: String? = nil,
        proxyStatus: ProxyStatus = .pending,
        proxyChecksum: String? = nil,
        proxyR2URL: String? = nil,
        proxyLUT: String? = nil,
        proxyColorSpace: String? = nil,
        narrativeMeta: NarrativeMeta? = nil,
        documentaryMeta: DocumentaryMeta? = nil,
        audioTracks: [AudioTrack] = [],
        syncResult: SyncResult = .unsynced,
        syncedAudioPath: String? = nil,
        cameraGroupId: String? = nil,
        cameraAngle: String? = nil,
        aiScores: AIScores? = nil,
        transcriptId: String? = nil,
        aiProcessingStatus: AIProcessingStatus = .pending,
        reviewStatus: ReviewStatus = .unreviewed,
        annotations: [Annotation] = [],
        approvalStatus: ApprovalStatus = .pending,
        approvedBy: String? = nil,
        approvedAt: String? = nil,
        ingestedAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        projectMode: ProjectMode,
        cameraMetadata: CameraMetadata? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.checksum = checksum
        self.sourcePath = sourcePath
        self.sourceSize = sourceSize
        self.sourceFormat = sourceFormat
        self.sourceFps = sourceFps
        self.sourceTimecodeStart = sourceTimecodeStart
        self.duration = duration
        self.proxyPath = proxyPath
        self.proxyStatus = proxyStatus
        self.proxyChecksum = proxyChecksum
        self.proxyR2URL = proxyR2URL
        self.proxyLUT = proxyLUT
        self.proxyColorSpace = proxyColorSpace
        self.narrativeMeta = narrativeMeta
        self.documentaryMeta = documentaryMeta
        self.audioTracks = audioTracks
        self.syncResult = syncResult
        self.syncedAudioPath = syncedAudioPath
        self.cameraGroupId = cameraGroupId
        self.cameraAngle = cameraAngle
        self.aiScores = aiScores
        self.transcriptId = transcriptId
        self.aiProcessingStatus = aiProcessingStatus
        self.reviewStatus = reviewStatus
        self.annotations = annotations
        self.approvalStatus = approvalStatus
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.ingestedAt = ingestedAt
        self.updatedAt = updatedAt
        self.projectMode = projectMode
        self.cameraMetadata = cameraMetadata
    }
}

// MARK: - Notification Types

public struct DeliveryTarget: Codable, Sendable {
    public let name: String
    public let method: DeliveryMethod
    public let address: String   // phone number, email, or Slack webhook URL
    
    public init(name: String, method: DeliveryMethod, address: String) {
        self.name = name
        self.method = method
        self.address = address
    }
}

public enum DeliveryMethod: String, Codable, Sendable {
    case iMessage, email, slack
}

// MARK: - Camera Metadata

public struct CameraMetadata: Codable, Sendable {
    public var cameraModel: String?
    public var cameraSerialNumber: String?
    public var lensModel: String?
    public var focalLength: Double?     // mm
    public var aperture: Double?        // f-stop
    public var iso: Int?                // ISO rating
    public var recordingFormat: String? // e.g., "ProRes 422 HQ", "BRAW"
    public var recordingDate: String?   // ISO 8601
    public var codec: String?           // FourCC string
    public var width: Int?
    public var height: Int?
    public var frameRate: Double?
    public var colorSpace: String?
    public var duration: Double?        // seconds
    public var bitrate: Int64?          // bits per second
    /// Raw slate / clapperboard OCR text from `SlateOCRDetector` (optional).
    public var slateOCRRawText: String?

    public init() {}
}

// MARK: - Project

public struct Project: Codable, Sendable, Identifiable {
    /// UUID v4
    public var id: String
    public var name: String
    public var mode: ProjectMode
    /// ISO 8601
    public var createdAt: String
    /// ISO 8601
    public var updatedAt: String
    /// Delivery targets for notifications
    public var notificationTargets: [DeliveryTarget]
    /// Auto-deliver when assembly is ready
    public var autoDeliverOnAssembly: Bool
    /// Recipients for the daily end-of-day digest (separate from assembly notifications).
    public var digestTargets: [DeliveryTarget]
    /// Local hour (0–23) to send the daily digest.
    public var digestHour: Int
    /// When true, schedules a daily digest while SLATE is running.
    public var dailyDigestEnabled: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        mode: ProjectMode,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        notificationTargets: [DeliveryTarget] = [],
        autoDeliverOnAssembly: Bool = true,
        digestTargets: [DeliveryTarget] = [],
        digestHour: Int = 21,
        dailyDigestEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notificationTargets = notificationTargets
        self.autoDeliverOnAssembly = autoDeliverOnAssembly
        self.digestTargets = digestTargets
        self.digestHour = digestHour
        self.dailyDigestEnabled = dailyDigestEnabled
    }
}

// MARK: - Assembly

public struct AssemblyClip: Codable, Sendable, Equatable {
    /// UUID — references Clip.id
    public var clipId: String
    /// Seconds
    public var inPoint: Double
    /// Seconds
    public var outPoint: Double
    public var role: AssemblyClipRole
    public var sceneLabel: String

    public init(
        clipId: String,
        inPoint: Double,
        outPoint: Double,
        role: AssemblyClipRole,
        sceneLabel: String
    ) {
        self.clipId = clipId
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.role = role
        self.sceneLabel = sceneLabel
    }

    /// Computed duration in seconds
    public var duration: Double { outPoint - inPoint }
}

public struct Assembly: Codable, Sendable, Identifiable {
    /// UUID v4
    public var id: String
    /// UUID — references Project.id
    public var projectId: String
    public var name: String
    public var mode: ProjectMode
    public var clips: [AssemblyClip]
    /// ISO 8601
    public var createdAt: String
    public var version: Int

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        name: String,
        mode: ProjectMode,
        clips: [AssemblyClip] = [],
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        version: Int = 1
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.mode = mode
        self.clips = clips
        self.createdAt = createdAt
        self.version = version
    }
}

// MARK: - Ingest progress (written by daemon, polled by desktop)

public enum IngestStage: String, Codable, Sendable, CaseIterable {
    case checksum
    case copy
    case verify
    case proxy
    case sync
    case complete
    case error
}

public struct IngestProgressItem: Codable, Sendable {
    public var filename: String
    /// 0.0–1.0
    public var progress: Double
    public var stage: IngestStage
    public var error: String?

    public init(filename: String, progress: Double, stage: IngestStage, error: String? = nil) {
        self.filename = filename
        self.progress = progress
        self.stage = stage
        self.error = error
    }
}

public struct IngestError: Codable, Sendable {
    public var filename: String
    public var message: String
    public var timestamp: String

    public init(filename: String, message: String, timestamp: String = ISO8601DateFormatter().string(from: Date())) {
        self.filename = filename
        self.message = message
        self.timestamp = timestamp
    }
}

public struct IngestProgressReport: Codable, Sendable {
    public var active: [IngestProgressItem]
    public var queued: Int
    public var errors: [IngestError]

    public init(active: [IngestProgressItem] = [], queued: Int = 0, errors: [IngestError] = []) {
        self.active = active
        self.queued = queued
        self.errors = errors
    }
}

// MARK: - Watch folder config

public struct WatchFolder: Codable, Sendable, Equatable {
    public var path: String
    public var projectId: String
    public var mode: ProjectMode
    /// Optional burn-in defaults for proxies ingested through this folder.
    public var burnInConfig: BurnInConfig?

    public init(path: String, projectId: String, mode: ProjectMode, burnInConfig: BurnInConfig? = nil) {
        self.path = path
        self.projectId = projectId
        self.mode = mode
        self.burnInConfig = burnInConfig
    }
}
