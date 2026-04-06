// SLATE — Sound report ingestion (production mixer logs)
// Parsed from CSV/PDF exports; matched to clips for notes and channel labels.

import Foundation

public struct SoundReportEntry: Codable, Sendable, Equatable {
    public let scene: String
    public let shotCode: String?
    public let takeNumber: Int
    public let audioFilename: String
    public let circled: Bool
    public let notes: String?
    public let timecode: String?
    public let channels: [String]

    public init(
        scene: String,
        shotCode: String?,
        takeNumber: Int,
        audioFilename: String,
        circled: Bool,
        notes: String?,
        timecode: String?,
        channels: [String]
    ) {
        self.scene = scene
        self.shotCode = shotCode
        self.takeNumber = takeNumber
        self.audioFilename = audioFilename
        self.circled = circled
        self.notes = notes
        self.timecode = timecode
        self.channels = channels
    }
}

public struct SoundReportMatchResult: Sendable {
    public let entry: SoundReportEntry
    public let matchedClipId: String?
    public let confidence: Double
    public let matchReason: String

    public init(
        entry: SoundReportEntry,
        matchedClipId: String?,
        confidence: Double,
        matchReason: String
    ) {
        self.entry = entry
        self.matchedClipId = matchedClipId
        self.confidence = confidence
        self.matchReason = matchReason
    }
}
