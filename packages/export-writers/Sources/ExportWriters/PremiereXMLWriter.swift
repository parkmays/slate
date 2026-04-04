import Foundation

public struct PremiereXMLWriter: ExportWriter {
    public let format: ExportFormat = .premiereXML

    public init() {}

    public func dryRun(context: ExportContext) throws {
        _ = try XMEMLDocumentBuilder.serializedData(context: context, variant: .premiere)
    }

    public func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        let data = try XMEMLDocumentBuilder.serializedData(context: context, variant: .premiere)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let preparation = try ExportPreparation(context: context)
        let filename = ExportPreparation.sanitizedFilename(
            prefix: "\(preparation.projectName)_\(preparation.assembly.name)-premiere-v\(preparation.assembly.version)",
            format: format
        )
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)

        return ExportArtifact(format: format, filePath: url.path, byteCount: data.count)
    }
}
