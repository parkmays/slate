// SLATE — Script import (Final Draft .fdx + plain PDF)
// Maps screenplay structure to clip scene metadata and slate OCR.

import Foundation
import SLATESharedTypes

#if canImport(PDFKit)
import PDFKit
#endif

// MARK: - Models

public struct ScriptScene: Codable, Sendable, Equatable {
    public let sceneNumber: String
    public let slugline: String
    public let pageNumber: Int
    public let characters: [String]
    public let synopsis: String?

    public init(
        sceneNumber: String,
        slugline: String,
        pageNumber: Int,
        characters: [String],
        synopsis: String?
    ) {
        self.sceneNumber = sceneNumber
        self.slugline = slugline
        self.pageNumber = pageNumber
        self.characters = characters
        self.synopsis = synopsis
    }
}

public struct ScriptImportResult: Sendable {
    public let title: String?
    public let scenes: [ScriptScene]
    public let totalPages: Int
    public let sourceURL: URL
    public let parsedAt: String

    public init(
        title: String?,
        scenes: [ScriptScene],
        totalPages: Int,
        sourceURL: URL,
        parsedAt: String
    ) {
        self.title = title
        self.scenes = scenes
        self.totalPages = totalPages
        self.sourceURL = sourceURL
        self.parsedAt = parsedAt
    }
}

public enum MappingSource: String, Codable, Sendable {
    case narrativeMeta
    case slateOCR
    case inferredFromSiblings
}

public struct ClipScriptMapping: Sendable {
    public let clipId: String
    public let sceneNumber: String
    public let scriptScene: ScriptScene?
    public let confidence: Double
    public let source: MappingSource

    public init(
        clipId: String,
        sceneNumber: String,
        scriptScene: ScriptScene?,
        confidence: Double,
        source: MappingSource
    ) {
        self.clipId = clipId
        self.sceneNumber = sceneNumber
        self.scriptScene = scriptScene
        self.confidence = confidence
        self.source = source
    }
}

public enum ScriptImportError: Error, Sendable {
    case unreadableFile(URL)
    case xmlParseFailed
    case emptyScript
    case pdfUnavailableOnPlatform
}

// MARK: - ScriptImporter

public enum ScriptImporter {
    fileprivate static let linesPerPage = 55
    private static func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }

    public static func parse(fdxURL: URL) throws -> ScriptImportResult {
        guard let data = try? Data(contentsOf: fdxURL) else {
            throw ScriptImportError.unreadableFile(fdxURL)
        }
        let parser = FDXScriptParser(data: data)
        try parser.parse()
        let scenes = parser.scenes
        guard !scenes.isEmpty else {
            throw ScriptImportError.emptyScript
        }
        let totalPages = max(1, (parser.paragraphLineCount + linesPerPage - 1) / linesPerPage)
        let parsedAt = iso8601Now()
        return ScriptImportResult(
            title: parser.title,
            scenes: scenes,
            totalPages: totalPages,
            sourceURL: fdxURL,
            parsedAt: parsedAt
        )
    }

    public static func parse(pdfURL: URL) throws -> ScriptImportResult {
        #if canImport(PDFKit)
        guard let doc = PDFDocument(url: pdfURL) else {
            throw ScriptImportError.unreadableFile(pdfURL)
        }
        let parsed = try PDFScriptParser.parse(document: doc)
        guard !parsed.scenes.isEmpty else {
            throw ScriptImportError.emptyScript
        }
        let parsedAt = iso8601Now()
        return ScriptImportResult(
            title: parsed.title,
            scenes: parsed.scenes,
            totalPages: max(1, parsed.totalPages),
            sourceURL: pdfURL,
            parsedAt: parsedAt
        )
        #else
        throw ScriptImportError.pdfUnavailableOnPlatform
        #endif
    }

    /// Maps ingested clips to imported script scenes using narrative slating, slate OCR text, and multi-cam group hints.
    public static func mapClipsToScript(clips: [Clip], script: ScriptImportResult) -> [ClipScriptMapping] {
        let sceneByNumber = script.scenes.reduce(into: [String: ScriptScene]()) { result, scene in
            let key = normalizeSceneNumber(scene.sceneNumber)
            // Keep first occurrence to avoid crashes on duplicate scene numbers.
            if result[key] == nil {
                result[key] = scene
            }
        }

        var mappingByClipId: [String: ClipScriptMapping] = [:]

        for clip in clips {
            if let meta = clip.narrativeMeta {
                let key = normalizeSceneNumber(meta.sceneNumber)
                if let sc = sceneByNumber[key] {
                    mappingByClipId[clip.id] = ClipScriptMapping(
                        clipId: clip.id,
                        sceneNumber: sc.sceneNumber,
                        scriptScene: sc,
                        confidence: 1.0,
                        source: .narrativeMeta
                    )
                }
            }
        }

        for clip in clips {
            if mappingByClipId[clip.id] != nil { continue }
            guard let raw = clip.cameraMetadata?.slateOCRRawText, !raw.isEmpty else { continue }
            if let sc = matchSlateOCR(rawText: raw, sceneByNumber: sceneByNumber, scenes: script.scenes) {
                mappingByClipId[clip.id] = ClipScriptMapping(
                    clipId: clip.id,
                    sceneNumber: sc.sceneNumber,
                    scriptScene: sc,
                    confidence: 0.90,
                    source: .slateOCR
                )
            }
        }

        let byGroup = Dictionary(grouping: clips) { $0.cameraGroupId ?? "" }
        for (_, groupClips) in byGroup {
            guard !groupClips.isEmpty, groupClips.first?.cameraGroupId != nil else { continue }
            let donors = groupClips.compactMap { mappingByClipId[$0.id] }.filter { $0.confidence >= 0.75 }
            guard let best = donors.max(by: { $0.confidence < $1.confidence }),
                  let donorScene = best.scriptScene
            else { continue }
            for clip in groupClips {
                if mappingByClipId[clip.id] != nil { continue }
                mappingByClipId[clip.id] = ClipScriptMapping(
                    clipId: clip.id,
                    sceneNumber: best.sceneNumber,
                    scriptScene: donorScene,
                    confidence: 0.75,
                    source: .inferredFromSiblings
                )
            }
        }

        return clips.map { clip in
            if let existing = mappingByClipId[clip.id] {
                return existing
            }
            return ClipScriptMapping(
                clipId: clip.id,
                sceneNumber: clip.narrativeMeta?.sceneNumber ?? "",
                scriptScene: nil,
                confidence: 0.0,
                source: .narrativeMeta
            )
        }
    }

    // MARK: - Matching helpers

    static func normalizeSceneNumber(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return t
    }

    private static func matchSlateOCR(
        rawText: String,
        sceneByNumber: [String: ScriptScene],
        scenes: [ScriptScene]
    ) -> ScriptScene? {
        let upper = rawText.uppercased()
        for sc in scenes {
            let slug = sc.slugline.uppercased()
                .replacingOccurrences(of: "—", with: "-")
                .replacingOccurrences(of: "–", with: "-")
            let compact = slug.replacingOccurrences(of: " ", with: "")
            let rawCompact = upper.replacingOccurrences(of: " ", with: "")
            if upper.contains(slug) || (!compact.isEmpty && rawCompact.contains(compact)) {
                return sc
            }
        }
        let pattern = #"\b(\d{1,3})([A-Z]?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(rawText.startIndex..., in: rawText)
        let matches = regex.matches(in: rawText, options: [], range: range)
        for m in matches {
            guard m.numberOfRanges >= 2,
                  let numR = Range(m.range(at: 1), in: rawText),
                  let sufR = Range(m.range(at: 2), in: rawText)
            else { continue }
            let num = String(rawText[numR])
            let suf = String(rawText[sufR])
            let combined = normalizeSceneNumber(num + suf)
            if let hit = sceneByNumber[combined] {
                return hit
            }
            let numOnly = normalizeSceneNumber(num)
            if let hit = sceneByNumber[numOnly] {
                return hit
            }
        }
        return nil
    }
}

// MARK: - FDX (XMLParser)

private final class FDXScriptParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var parser: XMLParser?

    private enum ParagraphKind: String {
        case sceneHeading = "Scene Heading"
        case action = "Action"
        case character = "Character"
        case dialogue = "Dialogue"
        case title = "Title"
    }

    private var paragraphType: String?
    private var sceneNumberAttr: String?
    private var textBuffer = ""
    private var inParagraph = false
    private var sequentialSceneIndex = 0

    private var currentSlugline: String?
    private var currentSceneNumber: String?
    private var currentCharacters: [String] = []
    private var currentSynopsis: String?
    private var wantsFirstAction = false
    /// Paragraph index (1-based line count) when the current scene’s heading paragraph ended.
    private var openedSceneAtParagraph = 0

    var title: String?
    private(set) var scenes: [ScriptScene] = []
    private(set) var paragraphLineCount = 0

    init(data: Data) {
        self.data = data
    }

    func parse() throws {
        let p = XMLParser(data: data)
        parser = p
        p.delegate = self
        guard p.parse() else {
            throw ScriptImportError.xmlParseFailed
        }
        flushScene()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "Paragraph" {
            inParagraph = true
            paragraphType = attributeDict["Type"]
            sceneNumberAttr = attributeDict["SceneNumber"]
            textBuffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inParagraph else { return }
        textBuffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "Paragraph" {
            inParagraph = false
            paragraphLineCount += 1
            let trimmed = textBuffer
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            defer {
                paragraphType = nil
                sceneNumberAttr = nil
                textBuffer = ""
            }
            guard let pType = paragraphType else { return }

            if pType == ParagraphKind.title.rawValue, !trimmed.isEmpty, title == nil {
                title = trimmed
                return
            }

            if pType == ParagraphKind.sceneHeading.rawValue, !trimmed.isEmpty {
                flushScene()
                sequentialSceneIndex += 1
                openedSceneAtParagraph = paragraphLineCount
                currentSlugline = trimmed
                if let attr = sceneNumberAttr, !attr.isEmpty {
                    currentSceneNumber = attr.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    currentSceneNumber = "\(sequentialSceneIndex)"
                }
                currentCharacters = []
                currentSynopsis = nil
                wantsFirstAction = true
                return
            }

            guard currentSlugline != nil else { return }

            switch pType {
            case ParagraphKind.action.rawValue:
                if wantsFirstAction, !trimmed.isEmpty {
                    let cap = trimmed.prefix(200)
                    currentSynopsis = String(cap)
                    wantsFirstAction = false
                }
            case ParagraphKind.character.rawValue:
                if !trimmed.isEmpty, !currentCharacters.contains(trimmed) {
                    currentCharacters.append(trimmed)
                }
            case ParagraphKind.dialogue.rawValue:
                break
            default:
                break
            }
        }
    }

    private func flushScene() {
        guard let slug = currentSlugline, let num = currentSceneNumber else { return }
        let start = max(1, openedSceneAtParagraph)
        let page = max(1, (start + ScriptImporter.linesPerPage - 1) / ScriptImporter.linesPerPage)
        let scene = ScriptScene(
            sceneNumber: num,
            slugline: slug,
            pageNumber: page,
            characters: currentCharacters,
            synopsis: currentSynopsis
        )
        scenes.append(scene)
        currentSlugline = nil
        currentSceneNumber = nil
        currentCharacters = []
        currentSynopsis = nil
        wantsFirstAction = false
    }
}

// MARK: - PDF (PDFKit)

#if canImport(PDFKit)
private enum PDFScriptParser {
    private static let headingRegex: NSRegularExpression = {
        let p = #"^(INT\.|EXT\.|INT\.\/EXT\.|I\/E)\s+.+\s+(DAY|NIGHT|CONTINUOUS|LATER)"#
        return try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }()

    private static let sceneNumLeadRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\d{1,3}[A-Za-z]?\s+"#, options: [])
    }()

    private static let sceneNumTailRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\s+\d{1,3}[A-Za-z]?$"#, options: [])
    }()

    static func parse(document: PDFDocument) throws -> (scenes: [ScriptScene], totalPages: Int, title: String?) {
        let pageCount = document.pageCount
        var allScenes: [ScriptScene] = []
        var sequential = 0

        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let pageText = page.string ?? ""
            let lines = splitPDFLines(pageText)
            var idx = 0
            while idx < lines.count {
                let line = lines[idx]
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "." || trimmed.isEmpty {
                    idx += 1
                    continue
                }
                if isSceneHeading(trimmed) {
                    sequential += 1
                    let (slug, sceneNum) = extractSceneHeadingAndNumber(trimmed, sequential: sequential)
                    var chars: [String] = []
                    var synopsis: String?
                    var wantAction = true
                    idx += 1
                    while idx < lines.count {
                        let inner = lines[idx]
                        let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t == "." { break }
                        if isSceneHeading(t) {
                            break
                        }
                        if leadingSpaceCount(inner) > 20, isAllCapsCharacterLine(t) {
                            if !chars.contains(t) { chars.append(t) }
                        } else if wantAction, !t.isEmpty, !isAllCapsCharacterLine(t) {
                            synopsis = String(t.prefix(200))
                            wantAction = false
                        }
                        idx += 1
                    }
                    let pageNum = i + 1
                    allScenes.append(
                        ScriptScene(
                            sceneNumber: sceneNum,
                            slugline: slug,
                            pageNumber: pageNum,
                            characters: chars,
                            synopsis: synopsis
                        )
                    )
                    continue
                }
                idx += 1
            }
        }

        return (allScenes, max(1, pageCount), nil)
    }

    private static func splitPDFLines(_ text: String) -> [String] {
        let parts = text.components(separatedBy: "\u{0c}")
        var lines: [String] = []
        for part in parts {
            let sub = part.components(separatedBy: CharacterSet.newlines)
            lines.append(contentsOf: sub)
        }
        return lines
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }

    private static func isSceneHeading(_ line: String) -> Bool {
        let r = NSRange(line.startIndex..., in: line)
        return headingRegex.firstMatch(in: line, options: [], range: r) != nil
    }

    private static func isAllCapsCharacterLine(_ line: String) -> Bool {
        guard line.count >= 2, line.rangeOfCharacter(from: .letters) != nil else { return false }
        let letters = line.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        return letters == letters.uppercased()
    }

    private static func extractSceneHeadingAndNumber(_ line: String, sequential: Int) -> (slug: String, number: String) {
        var working = line
        if let r = sceneNumLeadRegex.firstMatch(in: working, options: [], range: NSRange(working.startIndex..., in: working)),
           let range = Range(r.range, in: working) {
            let lead = String(working[range]).trimmingCharacters(in: .whitespaces)
            let numPart = lead.replacingOccurrences(of: " ", with: "")
            working.removeSubrange(range)
            let slug = working.trimmingCharacters(in: .whitespacesAndNewlines)
            if !numPart.isEmpty {
                return (slug, numPart)
            }
        }
        if let r = sceneNumTailRegex.firstMatch(in: working, options: [], range: NSRange(working.startIndex..., in: working)),
           let range = Range(r.range, in: working) {
            let tail = String(working[range]).trimmingCharacters(in: .whitespaces)
            let numPart = tail.replacingOccurrences(of: " ", with: "")
            working.removeSubrange(range)
            let slug = working.trimmingCharacters(in: .whitespacesAndNewlines)
            if !numPart.isEmpty {
                return (slug, numPart)
            }
        }
        return (line.trimmingCharacters(in: .whitespacesAndNewlines), "\(sequential)")
    }
}
#endif
