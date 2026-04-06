// SLATE — Sound report CSV/PDF parser and clip matcher
// No AppKit/UIKit — PDF via PDFKit when available.

import Foundation
import SLATESharedTypes

#if canImport(PDFKit)
import PDFKit
#endif

public enum SoundReportParserError: Error, Sendable, LocalizedError {
    case unsupportedFormat(String)
    case emptyDocument
    case pdfUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported sound report format: \(ext)"
        case .emptyDocument:
            return "Sound report contained no parseable rows"
        case .pdfUnavailable:
            return "PDF parsing requires PDFKit (macOS/iOS)"
        }
    }
}

public struct SoundReportParser: Sendable {
    public init() {}

    public func parse(fileURL: URL) async throws -> [SoundReportEntry] {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "csv", "tsv":
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
                throw SoundReportParserError.emptyDocument
            }
            return try parseCSV(text: text, delimiter: ext == "tsv" ? "\t" : ",")
        case "pdf":
            return try parsePDF(fileURL: fileURL)
        default:
            throw SoundReportParserError.unsupportedFormat(ext.isEmpty ? "(none)" : ext)
        }
    }

    public func match(entries: [SoundReportEntry], against clips: [Clip]) -> [SoundReportMatchResult] {
        entries.map { entry in
            if let (id, confidence, reason) = matchEntry(entry, clips: clips) {
                return SoundReportMatchResult(entry: entry, matchedClipId: id, confidence: confidence, matchReason: reason)
            }
            return SoundReportMatchResult(entry: entry, matchedClipId: nil, confidence: 0.0, matchReason: "No match")
        }
    }

    public func applyMatches(_ results: [SoundReportMatchResult], to store: GRDBStore) async throws {
        for result in results {
            guard result.confidence >= 0.70, let clipId = result.matchedClipId else { continue }
            guard var clip = try await store.getClip(byId: clipId) else { continue }
            let entry = result.entry

            clip.audioTracks = Self.mergeChannelLabels(existing: clip.audioTracks, channels: entry.channels)

            if entry.circled, clip.reviewStatus == .unreviewed {
                clip.reviewStatus = .circled
            }

            if let notes = entry.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                let ann = Annotation(
                    userId: "sound-report",
                    userDisplayName: "Sound Report",
                    timecodeIn: clip.sourceTimecodeStart,
                    body: notes,
                    source: "SoundReport"
                )
                clip.annotations.append(ann)
            }

            clip.updatedAt = ISO8601DateFormatter().string(from: Date())
            try await store.saveClip(clip)
        }
    }

    // MARK: - Matching

    private func matchEntry(_ entry: SoundReportEntry, clips: [Clip]) -> (String, Double, String)? {
        if let id = matchByFilename(entry, clips: clips) {
            return (id, 1.0, "Matched by audio filename")
        }
        if let id = matchByTimecode(entry, clips: clips) {
            return (id, 0.95, "Matched by timecode")
        }
        if let id = matchBySceneShotTake(entry, clips: clips) {
            return (id, 0.90, "Matched by scene/shot/take")
        }
        if let id = matchBySceneAndTake(entry, clips: clips) {
            return (id, 0.70, "Matched by scene and take number")
        }
        return nil
    }

    private func matchByFilename(_ entry: SoundReportEntry, clips: [Clip]) -> String? {
        let target = normalizeFilename(entry.audioFilename)
        guard !target.isEmpty else { return nil }
        for clip in clips {
            if let p = clip.syncedAudioPath {
                if normalizeFilename(URL(fileURLWithPath: p).lastPathComponent) == target {
                    return clip.id
                }
            }
            for t in clip.audioTracks {
                if normalizeFilename(t.channelLabel) == target { return clip.id }
                if t.channelLabel.lowercased().contains(".wav") || t.channelLabel.lowercased().contains(".aif") {
                    if normalizeFilename(t.channelLabel) == target { return clip.id }
                }
            }
        }
        return nil
    }

    private func matchByTimecode(_ entry: SoundReportEntry, clips: [Clip]) -> String? {
        guard let tc = entry.timecode?.trimmingCharacters(in: .whitespacesAndNewlines), !tc.isEmpty else {
            return nil
        }
        for clip in clips {
            guard let entryFrames = timecodeToFrameCount(tc, fps: clip.sourceFps) else { continue }
            guard let clipFrames = timecodeToFrameCount(clip.sourceTimecodeStart, fps: clip.sourceFps) else { continue }
            if abs(entryFrames - clipFrames) <= 2 {
                return clip.id
            }
        }
        return nil
    }

    private func matchBySceneShotTake(_ entry: SoundReportEntry, clips: [Clip]) -> String? {
        let scene = normalizeSceneToken(entry.scene)
        let shot = entry.shotCode.map { normalizeShotToken($0) }
        for clip in clips {
            guard let nm = clip.narrativeMeta else { continue }
            guard normalizeSceneToken(nm.sceneNumber) == scene else { continue }
            guard nm.takeNumber == entry.takeNumber else { continue }
            if let shot {
                guard normalizeShotToken(nm.shotCode) == shot else { continue }
            }
            return clip.id
        }
        return nil
    }

    private func matchBySceneAndTake(_ entry: SoundReportEntry, clips: [Clip]) -> String? {
        let shotEmpty = entry.shotCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        guard shotEmpty else { return nil }

        let scene = normalizeSceneToken(entry.scene)
        for clip in clips {
            guard let nm = clip.narrativeMeta else { continue }
            guard normalizeSceneToken(nm.sceneNumber) == scene else { continue }
            guard nm.takeNumber == entry.takeNumber else { continue }
            return clip.id
        }
        return nil
    }

    // MARK: - CSV

    private func parseCSV(text: String, delimiter: String) throws -> [SoundReportEntry] {
        let rows = splitCSVRows(text)
        guard let headerRow = rows.first else {
            throw SoundReportParserError.emptyDocument
        }
        let rawHeaders = parseCSVLine(headerRow, delimiter: delimiter)
        var indexMap: [String: Int] = [:]
        var channelColumnIndices: [Int] = []
        for (i, raw) in rawHeaders.enumerated() {
            let h = normalizeHeaderKey(raw)
            if indexMap[h] == nil { indexMap[h] = i }
            mapSynonyms(h, index: i, into: &indexMap)
            if Self.isLikelyChannelColumn(normalized: h, raw: raw) {
                channelColumnIndices.append(i)
            }
        }

        guard indexMap["scene"] != nil || indexMap["take"] != nil || indexMap["filename"] != nil else {
            throw SoundReportParserError.emptyDocument
        }

        var out: [SoundReportEntry] = []
        for rowText in rows.dropFirst() {
            let fields = parseCSVLine(rowText, delimiter: delimiter)
            guard !fields.isEmpty, fields.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                continue
            }
            if let entry = makeEntryFromCSVFields(
                fields: fields,
                indexMap: indexMap,
                channelColumnIndices: channelColumnIndices
            ) {
                out.append(entry)
            }
        }
        return out
    }

    private static func isLikelyChannelColumn(normalized: String, raw: String) -> Bool {
        if normalized.hasPrefix("track") { return true }
        if normalized.hasPrefix("ch") { return true }
        if normalized == "boom" || normalized.hasPrefix("lav") { return true }
        let lr = raw.lowercased()
        if lr.contains("ch 1") || lr.contains("ch 2") || lr.contains("track 1") || lr.contains("track 2") {
            return true
        }
        return false
    }

    private func mapSynonyms(_ normalized: String, index: Int, into map: inout [String: Int]) {
        switch normalized {
        case "shot", "setup": map["shot"] = index
        case "file", "filename", "audio", "audiofile", "audioname": map["filename"] = index
        case "circle", "ok", "select": map["circle"] = index
        case "note", "comment", "comments": map["notes"] = index
        case "tc", "tcin", "timecodein", "starttc", "timecode": map["timecode"] = index
        default:
            break
        }
    }

    private func makeEntryFromCSVFields(
        fields: [String],
        indexMap: [String: Int],
        channelColumnIndices: [Int]
    ) -> SoundReportEntry? {
        func field(_ key: String) -> String? {
            guard let idx = indexMap[key], idx < fields.count else { return nil }
            let v = fields[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : v
        }

        let scene = field("scene") ?? ""
        let shot = field("shot")
        let takeStr = field("take")
        let takeNumber: Int = {
            guard let takeStr else { return 0 }
            let digits = takeStr.filter { $0.isNumber }
            return Int(digits) ?? Int(takeStr) ?? 0
        }()
        let filename = field("filename") ?? ""
        guard !filename.isEmpty else { return nil }

        let circled: Bool = {
            guard let c = field("circle")?.lowercased() else { return false }
            if ["x", "✓", "●", "1", "yes", "true", "y", "ok"].contains(c) { return true }
            if c == "*" || c == "circled" { return true }
            return false
        }()

        let notes = field("notes")
        let tc = field("timecode")

        var channels: [String] = []
        for idx in channelColumnIndices where idx < fields.count {
            let v = fields[idx].trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { channels.append(v) }
        }

        return SoundReportEntry(
            scene: scene.isEmpty ? "—" : scene,
            shotCode: shot,
            takeNumber: takeNumber,
            audioFilename: filename,
            circled: circled,
            notes: notes,
            timecode: tc,
            channels: channels
        )
    }

    // MARK: - PDF

    private func parsePDF(fileURL: URL) throws -> [SoundReportEntry] {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: fileURL) else {
            throw SoundReportParserError.emptyDocument
        }
        var fullText = ""
        for i in 0..<doc.pageCount {
            if let page = doc.page(at: i), let t = page.string {
                fullText.append(t)
                fullText.append("\n")
            }
        }
        return parsePDFText(fullText)
        #else
        throw SoundReportParserError.pdfUnavailable
        #endif
    }

    private func parsePDFText(_ text: String) -> [SoundReportEntry] {
        let regex = try? NSRegularExpression(
            pattern: #"(\d+[A-Za-z]?)\s+([A-Za-z]?)\s+(\d+)\s+([\w\-\.]+\.(?:wav|aif|aiff|bwf|mxf))"#,
            options: [.caseInsensitive]
        )
        guard let regex else { return [] }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var results: [SoundReportEntry] = []

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 5 else { return }
            let scene = ns.substring(with: match.range(at: 1))
            let shotRaw = ns.substring(with: match.range(at: 2))
            let takeStr = ns.substring(with: match.range(at: 3))
            let file = ns.substring(with: match.range(at: 4))
            let lineRange = ns.lineRange(for: match.range)
            let line = ns.substring(with: lineRange)

            let shot: String? = shotRaw.trimmingCharacters(in: .whitespaces).isEmpty ? nil : shotRaw
            let take = Int(takeStr.filter(\.isNumber)) ?? Int(takeStr) ?? 0

            let circled = line.contains("●") || line.contains("✓") || line.range(of: "circle", options: .caseInsensitive) != nil

            results.append(
                SoundReportEntry(
                    scene: scene,
                    shotCode: shot,
                    takeNumber: take,
                    audioFilename: file,
                    circled: circled,
                    notes: nil,
                    timecode: nil,
                    channels: []
                )
            )
        }

        return results
    }

    // MARK: - CSV helpers

    private func normalizeHeaderKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func splitCSVRows(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func parseCSVLine(_ line: String, delimiter: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let scalars = Array(line)
        var i = 0
        let delim = delimiter.first!

        while i < scalars.count {
            let ch = scalars[i]
            if ch == "\"" {
                if inQuotes && i + 1 < scalars.count, scalars[i + 1] == "\"" {
                    current.append("\"")
                    i += 2
                    continue
                }
                inQuotes.toggle()
                i += 1
                continue
            }
            if !inQuotes, ch == delim {
                fields.append(current)
                current = ""
                i += 1
                continue
            }
            current.append(ch)
            i += 1
        }
        fields.append(current)
        return fields
    }

    // MARK: - Timecode

    private func timecodeToFrameCount(_ tc: String, fps: Double) -> Int? {
        let trimmed = tc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sep: Character = trimmed.contains(";") ? ";" : ":"
        let parts = trimmed.split(separator: sep).map(String.init)
        guard parts.count >= 4 else { return nil }

        let h = Int(parts[0]) ?? 0
        let m = Int(parts[1]) ?? 0
        let s = Int(parts[2]) ?? 0
        let f = Int(parts[3]) ?? 0

        let fpsRounded = max(1.0, fps)
        let _ = fpsRounded
        // Integer fps bucket for frame component (drop-frame nuance ignored; ±2 frames tolerance)
        let fpsInt = Int(fpsRounded.rounded())
        let base = ((h * 60 + m) * 60 + s) * fpsInt + f
        return base
    }

    // MARK: - Static merge

    /// Merges mixer channel names onto existing `AudioTrack` rows (internal for tests).
    static func mergeChannelLabels(existing: [AudioTrack], channels: [String]) -> [AudioTrack] {
        guard !channels.isEmpty else { return existing }
        if existing.isEmpty {
            return channels.enumerated().map { idx, label in
                AudioTrack(
                    trackIndex: idx,
                    role: .unknown,
                    channelLabel: label,
                    sampleRate: 48_000,
                    bitDepth: 24
                )
            }
        }

        var tracks = existing
        for (i, name) in channels.enumerated() {
            if i < tracks.count {
                var t = tracks[i]
                t.channelLabel = name
                tracks[i] = t
            } else {
                let sr = tracks.last?.sampleRate ?? 48_000
                let bd = tracks.last?.bitDepth ?? 24
                tracks.append(
                    AudioTrack(trackIndex: i, role: .iso, channelLabel: name, sampleRate: sr, bitDepth: bd)
                )
            }
        }
        return tracks.enumerated().map { i, t in
            var x = t
            x.trackIndex = i
            return x
        }
    }

    private func normalizeFilename(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeSceneToken(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeShotToken(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
