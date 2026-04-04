import Foundation
import SLATESharedTypes

struct ExportDimensions: Sendable, Equatable {
    let width: Int
    let height: Int

    static let fallbackHD = ExportDimensions(width: 1920, height: 1080)
}

struct PreparedAnnotation: Sendable, Equatable {
    let id: String
    let name: String
    let body: String
    let timelineStartFrame: Int
    let durationFrames: Int
}

struct PreparedClip: Sendable {
    let index: Int
    let assemblyClip: AssemblyClip
    let clip: Clip
    let filename: String
    let assetPath: String
    let assetURLString: String
    let audioSourcePath: String?
    let audioSourceURLString: String?
    let reelName: String
    let binName: String
    let rate: TimecodeRate
    let sourceStartFrame: Int
    let sourceInFrame: Int
    let sourceOutFrame: Int
    let sourceDurationFrames: Int
    let timelineStartFrame: Int
    let durationFrames: Int
    let reviewKeyword: String?
    let resolveColor: String?
    let audioRoleNames: [String]
    let markers: [PreparedAnnotation]
}

struct ExportPreparation: Sendable {
    let assembly: Assembly
    let projectName: String
    let dimensions: ExportDimensions
    let primaryRate: TimecodeRate
    let clips: [PreparedClip]
    let timelineMarkers: [PreparedAnnotation]
    let totalFrames: Int

    init(context: ExportContext) throws {
        guard !context.assembly.clips.isEmpty else {
            throw ExportWriterError.emptyAssembly
        }

        var preparedClips: [PreparedClip] = []
        var markers: [PreparedAnnotation] = []
        var timelineCursor = 0

        for (index, assemblyClip) in context.assembly.clips.enumerated() {
            guard let clip = context.clipsById[assemblyClip.clipId] else {
                throw ExportWriterError.missingClip(assemblyClip.clipId)
            }

            let rate = TimecodeRate(fps: clip.sourceFps, sourceTimecodeStart: clip.sourceTimecodeStart)
            let sourceStartFrame = rate.parseTimecode(clip.sourceTimecodeStart) ?? 0
            let sourceInFrame = max(0, rate.frames(fromSeconds: assemblyClip.inPoint))
            let rawOutFrame = max(sourceInFrame + 1, rate.frames(fromSeconds: assemblyClip.outPoint))
            let sourceDurationFrames = max(rawOutFrame, rate.frames(fromSeconds: clip.duration))
            let sourceOutFrame = min(max(rawOutFrame, sourceInFrame + 1), max(sourceDurationFrames, sourceInFrame + 1))
            let durationFrames = max(1, sourceOutFrame - sourceInFrame)
            let filename = URL(fileURLWithPath: clip.sourcePath).lastPathComponent
            let assetPath = clip.proxyPath ?? clip.sourcePath
            let assetURLString = URL(fileURLWithPath: assetPath).absoluteString
            let audioPath = clip.syncedAudioPath ?? clip.sourcePath
            let audioURLString = URL(fileURLWithPath: audioPath).absoluteString
            let clipMarkers = Self.prepareMarkers(
                for: clip,
                rate: rate,
                sourceStartFrame: sourceStartFrame,
                sourceInFrame: sourceInFrame,
                durationFrames: durationFrames,
                timelineStartFrame: timelineCursor
            )

            let preparedClip = PreparedClip(
                index: index,
                assemblyClip: assemblyClip,
                clip: clip,
                filename: filename,
                assetPath: assetPath,
                assetURLString: assetURLString,
                audioSourcePath: clip.syncedAudioPath ?? clip.sourcePath,
                audioSourceURLString: audioURLString,
                reelName: Self.makeEDLReelName(assemblyClip: assemblyClip, clip: clip),
                binName: Self.makeBinName(for: clip, assemblyClip: assemblyClip),
                rate: rate,
                sourceStartFrame: sourceStartFrame,
                sourceInFrame: sourceInFrame,
                sourceOutFrame: sourceOutFrame,
                sourceDurationFrames: max(sourceDurationFrames, sourceOutFrame),
                timelineStartFrame: timelineCursor,
                durationFrames: durationFrames,
                reviewKeyword: Self.keyword(for: clip.reviewStatus),
                resolveColor: Self.resolveColor(for: clip.reviewStatus),
                audioRoleNames: Self.audioRoles(for: clip.audioTracks),
                markers: clipMarkers
            )

            preparedClips.append(preparedClip)
            markers.append(contentsOf: clipMarkers)
            timelineCursor += durationFrames
        }

        self.assembly = context.assembly
        self.projectName = context.projectName ?? "Project \(context.assembly.projectId)"
        self.dimensions = .fallbackHD
        self.primaryRate = preparedClips.first?.rate ?? TimecodeRate(fps: 24, sourceTimecodeStart: "01:00:00:00")
        self.clips = preparedClips
        self.timelineMarkers = markers.sorted { $0.timelineStartFrame < $1.timelineStartFrame }
        self.totalFrames = max(timelineCursor, 1)
    }

    static func sanitizedFilename(prefix: String, format: ExportFormat) -> String {
        let safePrefix = prefix
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return "\(safePrefix).\(format.fileExtension)"
    }

    private static func prepareMarkers(
        for clip: Clip,
        rate: TimecodeRate,
        sourceStartFrame: Int,
        sourceInFrame: Int,
        durationFrames: Int,
        timelineStartFrame: Int
    ) -> [PreparedAnnotation] {
        clip.annotations.compactMap { annotation in
            guard let absoluteStart = rate.parseTimecode(annotation.timecodeIn) else {
                return PreparedAnnotation(
                    id: annotation.id,
                    name: annotation.userDisplayName,
                    body: annotation.body,
                    timelineStartFrame: timelineStartFrame,
                    durationFrames: 1
                )
            }

            let relativeStart = absoluteStart - sourceStartFrame - sourceInFrame
            let clampedStart = max(0, min(durationFrames - 1, relativeStart))

            let annotationDurationFrames: Int
            if let timecodeOut = annotation.timecodeOut,
               let absoluteEnd = rate.parseTimecode(timecodeOut) {
                annotationDurationFrames = max(1, absoluteEnd - absoluteStart)
            } else {
                annotationDurationFrames = 1
            }

            return PreparedAnnotation(
                id: annotation.id,
                name: annotation.userDisplayName,
                body: annotation.body,
                timelineStartFrame: timelineStartFrame + clampedStart,
                durationFrames: max(1, min(annotationDurationFrames, durationFrames - clampedStart))
            )
        }
    }

    private static func keyword(for reviewStatus: ReviewStatus) -> String? {
        switch reviewStatus {
        case .circled:
            return "Circled"
        case .flagged:
            return "Flagged"
        case .deprioritized:
            return "Deprioritized"
        case .unreviewed, .x:
            return nil
        }
    }

    private static func resolveColor(for reviewStatus: ReviewStatus) -> String? {
        switch reviewStatus {
        case .circled:
            return "Green"
        case .flagged:
            return "Yellow"
        case .deprioritized:
            return "Red"
        case .unreviewed, .x:
            return nil
        }
    }

    private static func audioRoles(for tracks: [AudioTrack]) -> [String] {
        let roles = tracks.map { track -> String in
            switch track.role {
            case .boom:
                return "dialogue.boom"
            case .lav:
                return "dialogue.lav"
            case .mix:
                return "dialogue.mix"
            case .iso, .unknown:
                return "dialogue.mix"
            }
        }

        return roles.isEmpty ? ["dialogue.mix"] : roles
    }

    private static func makeBinName(for clip: Clip, assemblyClip: AssemblyClip) -> String {
        switch clip.projectMode {
        case .narrative:
            if let scene = clip.narrativeMeta?.sceneNumber, !scene.isEmpty {
                return "Scene \(scene)"
            }
            return "Scene \(assemblyClip.sceneLabel)"
        case .documentary:
            if let subjectName = clip.documentaryMeta?.subjectName, !subjectName.isEmpty {
                return subjectName
            }
            return assemblyClip.sceneLabel
        }
    }

    private static func makeEDLReelName(assemblyClip: AssemblyClip, clip: Clip) -> String {
        let candidates: [String] = [
            assemblyClip.sceneLabel,
            clip.narrativeMeta.map { "\($0.sceneNumber)\($0.shotCode)\($0.takeNumber)" },
            URL(fileURLWithPath: clip.sourcePath).deletingPathExtension().lastPathComponent,
            clip.id
        ].compactMap { $0 }

        for candidate in candidates {
            let sanitized = candidate
                .uppercased()
                .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            if !sanitized.isEmpty, sanitized.count <= 8 {
                return sanitized
            }
        }

        let fallback = clip.id
            .uppercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return String(fallback.prefix(8))
    }
}

struct TimecodeRate: Sendable, Equatable {
    let fps: Double
    let nominalFramesPerSecond: Int
    let isDropFrame: Bool

    init(fps: Double, sourceTimecodeStart: String) {
        self.fps = fps
        if abs(fps - 23.976) < 0.01 {
            self.nominalFramesPerSecond = 24
        } else if abs(fps - 29.97) < 0.01 {
            self.nominalFramesPerSecond = 30
        } else {
            self.nominalFramesPerSecond = max(Int(fps.rounded()), 1)
        }
        self.isDropFrame = sourceTimecodeStart.contains(";")
    }

    var frameDurationString: String {
        if abs(fps - 23.976) < 0.01 {
            return "1001/24000s"
        }
        if abs(fps - 29.97) < 0.01 {
            return "1001/30000s"
        }
        return "1/\(nominalFramesPerSecond)s"
    }

    var timebase: Int { nominalFramesPerSecond }

    var ntsc: Bool {
        abs(fps.rounded() - fps) > 0.01
    }

    var fcpxmlTimecodeFormat: String {
        isDropFrame ? "DF" : "NDF"
    }

    var edlFrameMode: String {
        isDropFrame ? "DROP FRAME" : "NON-DROP FRAME"
    }

    func frames(fromSeconds seconds: Double) -> Int {
        max(Int((seconds * fps).rounded()), 0)
    }

    func secondsString(fromFrames frames: Int) -> String {
        let seconds = Double(frames) / fps
        return "\(String(format: "%.6f", seconds))s"
    }

    func parseTimecode(_ value: String) -> Int? {
        let cleaned = value.replacingOccurrences(of: ";", with: ":")
        let parts = cleaned.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 4 else {
            return nil
        }

        let hours = parts[0]
        let minutes = parts[1]
        let seconds = parts[2]
        let frames = parts[3]
        let totalMinutes = (hours * 60) + minutes
        let baseFrames = (((hours * 3600) + (minutes * 60) + seconds) * nominalFramesPerSecond) + frames

        if isDropFrame {
            let droppedFrames = 2 * (totalMinutes - (totalMinutes / 10))
            return baseFrames - droppedFrames
        }

        return baseFrames
    }

    func timecodeString(forFrames frameCount: Int) -> String {
        let normalizedFrames = max(frameCount, 0)
        if isDropFrame {
            let fps = nominalFramesPerSecond
            let dropFrames = 2
            let framesPerHour = fps * 60 * 60 - dropFrames * 54
            let framesPer24Hours = framesPerHour * 24
            let framesPer10Minutes = fps * 60 * 10 - dropFrames * 9
            let framesPerMinute = fps * 60 - dropFrames

            var frames = normalizedFrames % framesPer24Hours
            let tenMinuteChunks = frames / framesPer10Minutes
            let remainingFrames = frames % framesPer10Minutes
            frames += dropFrames * 9 * tenMinuteChunks
            if remainingFrames >= dropFrames {
                frames += dropFrames * ((remainingFrames - dropFrames) / framesPerMinute)
            }

            let hours = frames / (fps * 3600)
            let minutes = (frames / (fps * 60)) % 60
            let seconds = (frames / fps) % 60
            let frame = frames % fps
            return String(format: "%02d:%02d:%02d;%02d", hours, minutes, seconds, frame)
        }

        let fps = nominalFramesPerSecond
        let hours = normalizedFrames / (fps * 3600)
        let minutes = (normalizedFrames / (fps * 60)) % 60
        let seconds = (normalizedFrames / fps) % 60
        let frame = normalizedFrames % fps
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frame)
    }
}

enum XMLSerialization {
    static func data(from root: XMLElement) throws -> Data {
        let document = XMLDocument(rootElement: root)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        let data = document.xmlData(options: [.nodePrettyPrint])
        _ = try XMLDocument(data: data)
        return data
    }
}

extension XMLElement {
    convenience init(name: String, attributes: [String: String] = [:], children: [XMLNode] = []) {
        self.init(name: name)
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode)
        }
        children.forEach(addChild)
    }

    static func textNode(name: String, value: String) -> XMLElement {
        let element = XMLElement(name: name)
        element.stringValue = value
        return element
    }
}
