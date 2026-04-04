import Foundation
import SLATESharedTypes

public enum ExportFormat: String, Codable, Sendable, CaseIterable {
    case assemblyArchive = "assembly_archive"
    case fcpxml
    case cmx3600EDL = "cmx3600_edl"
    case aaf
    case premiereXML = "premiere_xml"
    case davinciResolveXML = "davinci_resolve_xml"

    public var fileExtension: String {
        switch self {
        case .assemblyArchive:
            return "slateassembly.json"
        case .fcpxml:
            return "fcpxml"
        case .cmx3600EDL:
            return "edl"
        case .aaf:
            return "aaf"
        case .premiereXML, .davinciResolveXML:
            return "xml"
        }
    }

    public var displayName: String {
        switch self {
        case .assemblyArchive:
            return "Assembly Archive"
        case .fcpxml:
            return "FCPXML"
        case .cmx3600EDL:
            return "CMX 3600 EDL"
        case .aaf:
            return "AAF"
        case .premiereXML:
            return "Premiere XML"
        case .davinciResolveXML:
            return "Resolve XML"
        }
    }
}

public struct ExportContext: Sendable {
    public var assembly: Assembly
    public var clipsById: [String: Clip]
    public var projectName: String?

    public init(
        assembly: Assembly,
        clipsById: [String: Clip],
        projectName: String? = nil
    ) {
        self.assembly = assembly
        self.clipsById = clipsById
        self.projectName = projectName
    }
}

public struct ExportArtifact: Sendable, Equatable {
    public var format: ExportFormat
    public var filePath: String
    public var byteCount: Int
    public var exportedAt: String

    public init(
        format: ExportFormat,
        filePath: String,
        byteCount: Int,
        exportedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.format = format
        self.filePath = filePath
        self.byteCount = byteCount
        self.exportedAt = exportedAt
    }
}

public enum ExportWriterError: Error, LocalizedError {
    case unsupportedFormat(ExportFormat)
    case missingClip(String)
    case emptyAssembly
    case invalidExport(String)
    case externalToolUnavailable(String)
    case externalToolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Export format \(format.rawValue) is not implemented yet."
        case .missingClip(let clipId):
            return "Assembly references clip \(clipId), but it was not available for export."
        case .emptyAssembly:
            return "The assembly has no clips to export."
        case .invalidExport(let reason):
            return "The export could not be built: \(reason)"
        case .externalToolUnavailable(let tool):
            return "The export requires \(tool), but it was not available."
        case .externalToolFailed(let message):
            return "The export helper failed: \(message)"
        }
    }
}

public protocol ExportWriter: Sendable {
    var format: ExportFormat { get }

    func dryRun(context: ExportContext) throws
    func export(context: ExportContext, to directory: URL) throws -> ExportArtifact
}

public enum ExportWriterFactory {
    public static func writer(for format: ExportFormat) -> any ExportWriter {
        switch format {
        case .assemblyArchive:
            return AssemblyArchiveWriter()
        case .fcpxml:
            return FCPXMLWriter()
        case .cmx3600EDL:
            return CMX3600EDLWriter()
        case .aaf:
            return AAFWriter()
        case .premiereXML:
            return PremiereXMLWriter()
        case .davinciResolveXML:
            return DaVinciResolveXMLWriter()
        }
    }
}

struct UnsupportedExportWriter: ExportWriter {
    let format: ExportFormat

    func dryRun(context: ExportContext) throws {
        _ = context
        throw ExportWriterError.unsupportedFormat(format)
    }

    func export(context: ExportContext, to directory: URL) throws -> ExportArtifact {
        _ = context
        _ = directory
        throw ExportWriterError.unsupportedFormat(format)
    }
}
