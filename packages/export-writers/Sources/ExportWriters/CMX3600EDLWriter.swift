import Foundation

public struct CMX3600EDLWriter: ExportWriter {
    public let format: ExportFormat = .cmx3600EDL

    public init() {}

    public func dryRun(context: ExportContext) throws {
        _ = try Self.render(context: context)
    }

    public func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        let contents = try Self.render(context: context)
        let data = Data(contents.utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let preparation = try ExportPreparation(context: context)
        let filename = ExportPreparation.sanitizedFilename(
            prefix: "\(preparation.projectName)_\(preparation.assembly.name)-v\(preparation.assembly.version)",
            format: format
        )
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)

        return ExportArtifact(format: format, filePath: url.path, byteCount: data.count)
    }

    static func render(context: ExportContext) throws -> String {
        let preparation = try ExportPreparation(context: context)
        var lines: [String] = []
        lines.append("TITLE: \(preparation.assembly.name)")
        lines.append("FCM: \(preparation.primaryRate.edlFrameMode)")
        lines.append("")

        for (index, preparedClip) in preparation.clips.enumerated() {
            if preparedClip.reelName.count > 8 {
                throw ExportWriterError.invalidExport("EDL reel names must be 8 characters or fewer.")
            }

            let eventNumber = String(format: "%03d", index + 1)
            let sourceIn = preparedClip.rate.timecodeString(
                forFrames: preparedClip.sourceStartFrame + preparedClip.sourceInFrame
            )
            let sourceOut = preparedClip.rate.timecodeString(
                forFrames: preparedClip.sourceStartFrame + preparedClip.sourceOutFrame
            )
            let recordIn = preparation.primaryRate.timecodeString(forFrames: preparedClip.timelineStartFrame)
            let recordOut = preparation.primaryRate.timecodeString(
                forFrames: preparedClip.timelineStartFrame + preparedClip.durationFrames
            )

            lines.append(
                "\(eventNumber)  \(preparedClip.reelName.padding(toLength: 8, withPad: " ", startingAt: 0)) V     C        \(sourceIn) \(sourceOut) \(recordIn) \(recordOut)"
            )
            lines.append("* FROM CLIP NAME: \(preparedClip.filename)")
            lines.append("* SOURCE FILE: \(preparedClip.clip.sourcePath)")
            if let keyword = preparedClip.reviewKeyword {
                lines.append("* REVIEW STATUS: \(keyword)")
            }
            for marker in preparedClip.markers {
                let markerTimecode = preparation.primaryRate.timecodeString(forFrames: marker.timelineStartFrame)
                lines.append("* LOC: \(markerTimecode) \(marker.body)")
            }
            lines.append("")
        }

        let rendered = lines.joined(separator: "\n")
        if !rendered.contains("FROM CLIP NAME") {
            throw ExportWriterError.invalidExport("EDL export did not include clip comments.")
        }
        return rendered
    }
}
