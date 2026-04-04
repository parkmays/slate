import Foundation

public struct DaVinciResolveXMLWriter: ExportWriter {
    public let format: ExportFormat = .davinciResolveXML

    public init() {}

    public func dryRun(context: ExportContext) throws {
        _ = try XMEMLDocumentBuilder.serializedData(context: context, variant: .resolve)
    }

    public func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        let data = try XMEMLDocumentBuilder.serializedData(context: context, variant: .resolve)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let preparation = try ExportPreparation(context: context)
        let filename = ExportPreparation.sanitizedFilename(
            prefix: "\(preparation.projectName)_\(preparation.assembly.name)-resolve-v\(preparation.assembly.version)",
            format: format
        )
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)

        return ExportArtifact(format: format, filePath: url.path, byteCount: data.count)
    }
}
