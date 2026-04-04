import Foundation
import SLATESharedTypes

struct AAFInspection: Codable, Sendable {
    let topLevelName: String
    let slotNames: [String]
    let masterMobNames: [String]
    let locatorURLs: [String]
}

struct AAFExportManifest: Codable, Sendable {
    struct Dimensions: Codable, Sendable {
        let width: Int
        let height: Int
    }

    struct AudioTrackRecord: Codable, Sendable {
        let trackIndex: Int
        let role: String
        let channelLabel: String
        let sampleRate: Double
        let bitDepth: Int
    }

    struct ClipRecord: Codable, Sendable {
        let clipId: String
        let name: String
        let sceneLabel: String
        let videoPath: String
        let audioPath: String?
        let sourcePath: String
        let durationFrames: Int
        let sourceInFrame: Int
        let timelineStartFrame: Int
        let reviewKeyword: String?
        let audioTracks: [AudioTrackRecord]
    }

    let projectName: String
    let assemblyName: String
    let version: Int
    let fps: Double
    let dropFrame: Bool
    let dimensions: Dimensions
    let clips: [ClipRecord]
}

enum AAFBridge {
    static func inspect(fileAt url: URL) throws -> AAFInspection {
        let data = try run(arguments: ["inspect", url.path])
        return try JSONDecoder().decode(AAFInspection.self, from: data)
    }

    static func write(manifest: AAFExportManifest, to destinationURL: URL) throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-aaf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let manifestURL = tempDirectory.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)

        _ = try run(arguments: ["write", manifestURL.path, destinationURL.path])
    }

    private static func run(arguments: [String]) throws -> Data {
        guard Bundle.module.url(forResource: "aaf_bridge", withExtension: "py") != nil else {
            throw ExportWriterError.externalToolUnavailable("the bundled AAF bridge")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

        guard let scriptURL = Bundle.module.url(forResource: "aaf_bridge", withExtension: "py"),
              let resourceURL = Bundle.module.resourceURL else {
            throw ExportWriterError.externalToolUnavailable("the bundled AAF bridge")
        }

        process.arguments = ["python3", scriptURL.path] + arguments
        var environment = ProcessInfo.processInfo.environment
        let pythonPath = resourceURL.appendingPathComponent("python").path
        environment["PYTHONPATH"] = [pythonPath, environment["PYTHONPATH"]]
            .compactMap { $0 }
            .joined(separator: ":")
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData.isEmpty ? stdoutData : stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw ExportWriterError.externalToolFailed(message)
        }

        return stdoutData
    }
}

public struct AAFWriter: ExportWriter {
    public let format: ExportFormat = .aaf

    public init() {}

    public func dryRun(context: ExportContext) throws {
        let preparation = try ExportPreparation(context: context)
        let manifest = Self.manifest(from: preparation)
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-aaf-dry-run-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let tempFile = tempDirectory.appendingPathComponent("dry-run.aaf")
        try AAFBridge.write(manifest: manifest, to: tempFile)
        _ = try AAFBridge.inspect(fileAt: tempFile)
    }

    public func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        let preparation = try ExportPreparation(context: context)
        let manifest = Self.manifest(from: preparation)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let filename = ExportPreparation.sanitizedFilename(
            prefix: "\(preparation.projectName)_\(preparation.assembly.name)-aaf-v\(preparation.assembly.version)",
            format: format
        )
        let outputURL = directory.appendingPathComponent(filename)
        try AAFBridge.write(manifest: manifest, to: outputURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return ExportArtifact(format: format, filePath: outputURL.path, byteCount: byteCount)
    }

    static func manifest(from preparation: ExportPreparation) -> AAFExportManifest {
        AAFExportManifest(
            projectName: preparation.projectName,
            assemblyName: preparation.assembly.name,
            version: preparation.assembly.version,
            fps: preparation.primaryRate.fps,
            dropFrame: preparation.primaryRate.isDropFrame,
            dimensions: .init(width: preparation.dimensions.width, height: preparation.dimensions.height),
            clips: preparation.clips.map { preparedClip in
                AAFExportManifest.ClipRecord(
                    clipId: preparedClip.clip.id,
                    name: preparedClip.filename,
                    sceneLabel: preparedClip.assemblyClip.sceneLabel,
                    videoPath: preparedClip.assetPath,
                    audioPath: preparedClip.audioSourcePath,
                    sourcePath: preparedClip.clip.sourcePath,
                    durationFrames: preparedClip.durationFrames,
                    sourceInFrame: preparedClip.sourceInFrame,
                    timelineStartFrame: preparedClip.timelineStartFrame,
                    reviewKeyword: preparedClip.reviewKeyword,
                    audioTracks: preparedClip.clip.audioTracks.map {
                        .init(
                            trackIndex: $0.trackIndex,
                            role: $0.role.rawValue,
                            channelLabel: $0.channelLabel,
                            sampleRate: $0.sampleRate,
                            bitDepth: $0.bitDepth
                        )
                    }
                )
            }
        )
    }
}
