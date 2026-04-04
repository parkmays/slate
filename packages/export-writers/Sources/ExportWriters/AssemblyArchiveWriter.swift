import Foundation
import SLATESharedTypes

public struct AssemblyArchiveWriter: ExportWriter {
    public let format: ExportFormat = .assemblyArchive

    public init() {}

    public func dryRun(context: ExportContext) throws {
        _ = try Self.makePayload(from: context)
    }

    public func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        let payload = try Self.makePayload(from: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = sanitizedFilename(for: context.assembly)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)

        return ExportArtifact(
            format: format,
            filePath: url.path,
            byteCount: data.count
        )
    }

    private func sanitizedFilename(for assembly: Assembly) -> String {
        let name = assembly.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return "\(name)-v\(assembly.version).\(format.fileExtension)"
    }

    private static func makePayload(from context: ExportContext) throws -> AssemblyArchivePayload {
        let clips = try context.assembly.clips.map { assemblyClip in
            guard let clip = context.clipsById[assemblyClip.clipId] else {
                throw ExportWriterError.missingClip(assemblyClip.clipId)
            }

            return AssemblyArchivePayload.ClipSnapshot(
                clipId: clip.id,
                checksum: clip.checksum,
                filename: URL(fileURLWithPath: clip.sourcePath).lastPathComponent,
                sourcePath: clip.sourcePath,
                proxyPath: clip.proxyPath,
                reviewStatus: clip.reviewStatus.rawValue,
                sceneLabel: assemblyClip.sceneLabel,
                role: assemblyClip.role.rawValue,
                inPoint: assemblyClip.inPoint,
                outPoint: assemblyClip.outPoint,
                annotations: clip.annotations
            )
        }

        return AssemblyArchivePayload(
            assembly: context.assembly,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            clips: clips
        )
    }
}

struct AssemblyArchivePayload: Codable, Sendable {
    struct ClipSnapshot: Codable, Sendable {
        var clipId: String
        var checksum: String?
        var filename: String
        var sourcePath: String
        var proxyPath: String?
        var reviewStatus: String
        var sceneLabel: String
        var role: String
        var inPoint: Double
        var outPoint: Double
        var annotations: [Annotation]
    }

    var assembly: Assembly
    var exportedAt: String
    var clips: [ClipSnapshot]
}
