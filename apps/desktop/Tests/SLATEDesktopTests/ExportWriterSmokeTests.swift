import Foundation
import Testing
@testable import SLATECore
@testable import SLATESharedTypes
import ExportWriters

// MARK: - Helpers

private let fixtureProject = Project(id: "smoke-proj", name: "Smoke Test Project", mode: .narrative)

/// Three narrative clips that span scene 1, shots A and B.
private let fixtureClips: [Clip] = [
    makeSmokeclip(id: "1A-1", scene: "1", shot: "A", take: 1, score: 88),
    makeSmokeclip(id: "1A-2", scene: "1", shot: "A", take: 2, score: 72),
    makeSmokeclip(id: "1B-1", scene: "1", shot: "B", take: 1, score: 91),
]

private func makeSmokeclip(
    id: String,
    scene: String,
    shot: String,
    take: Int,
    score: Double
) -> Clip {
    Clip(
        id: id,
        projectId: fixtureProject.id,
        checksum: String(repeating: "0", count: 64),
        sourcePath: "/Volumes/BRAW/\(id).braw",
        sourceSize: 2_000_000,
        sourceFormat: .braw,
        sourceFps: 24,
        sourceTimecodeStart: "01:00:00:00",
        duration: 10,
        proxyPath: "/tmp/proxy/\(id)_proxy.mp4",
        proxyStatus: .ready,
        narrativeMeta: .init(sceneNumber: scene, shotCode: shot, takeNumber: take, cameraId: "A"),
        aiScores: AIScores(
            composite: score,
            focus: score,
            exposure: score,
            stability: score,
            audio: score,
            scoredAt: ISO8601DateFormatter().string(from: Date()),
            modelVersion: "smoke-fixture"
        ),
        reviewStatus: .circled,
        projectMode: .narrative
    )
}

/// Build a minimal `ExportContext` and `Assembly` using the fixture clips.
@MainActor
private func makeContext() async throws -> ExportContext {
    let tempDB = FileManager.default.temporaryDirectory
        .appendingPathComponent("slate-smoke-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: tempDB) }

    let store = AssemblyStore(dbPath: tempDB.path)
    await store.load(project: fixtureProject)
    try await store.generateAssembly(
        project: fixtureProject,
        clips: fixtureClips,
        options: AssemblyGenerationOptions(name: "Smoke Assembly")
    )

    guard let assembly = store.currentAssembly else {
        struct MissingAssembly: Error {}
        throw MissingAssembly()
    }

    let lookup = Dictionary(uniqueKeysWithValues: fixtureClips.map { ($0.id, $0) })
    return ExportContext(assembly: assembly, clipsById: lookup, projectName: fixtureProject.name)
}

// MARK: - Suite: dryRun passes for all formats

@Suite("ExportWriter dryRun — all formats")
struct ExportWriterDryRunTests {

    @Test("FCPXML dryRun succeeds")
    func fcpxmlDryRun() async throws {
        let context = try await makeContext()
        try ExportWriterFactory.writer(for: .fcpxml).dryRun(context: context)
    }

    @Test("CMX 3600 EDL dryRun succeeds")
    func cmx3600DryRun() async throws {
        let context = try await makeContext()
        try ExportWriterFactory.writer(for: .cmx3600EDL).dryRun(context: context)
    }

    @Test("Premiere XML dryRun succeeds")
    func premiereXMLDryRun() async throws {
        let context = try await makeContext()
        try ExportWriterFactory.writer(for: .premiereXML).dryRun(context: context)
    }

    @Test("DaVinci Resolve XML dryRun succeeds")
    func davinciResolveXMLDryRun() async throws {
        let context = try await makeContext()
        try ExportWriterFactory.writer(for: .davinciResolveXML).dryRun(context: context)
    }

    @Test("Assembly Archive dryRun succeeds")
    func assemblyArchiveDryRun() async throws {
        let context = try await makeContext()
        try ExportWriterFactory.writer(for: .assemblyArchive).dryRun(context: context)
    }

    @Test("AAF dryRun succeeds (or throws externalToolUnavailable only)")
    func aafDryRun() async throws {
        let context = try await makeContext()
        do {
            try ExportWriterFactory.writer(for: .aaf).dryRun(context: context)
        } catch ExportWriterError.externalToolUnavailable {
            // Acceptable in CI — pyaaf2 bridge may not be present
        }
    }
}

// MARK: - Suite: export writes non-empty files

@Suite("ExportWriter export — file output")
struct ExportWriterFileOutputTests {

    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-smoke-out-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("FCPXML export produces a non-empty file")
    func fcpxmlExport() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .fcpxml).export(context: context, to: dir)
        #expect(FileManager.default.fileExists(atPath: artifact.filePath))
        #expect(artifact.byteCount > 0)
    }

    @Test("FCPXML file contains <fcpxml version= declaration")
    func fcpxmlContainsHeader() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .fcpxml).export(context: context, to: dir)
        let contents = try String(contentsOfFile: artifact.filePath, encoding: .utf8)
        #expect(contents.contains("<fcpxml version="))
    }

    @Test("CMX 3600 EDL export produces a non-empty file")
    func cmx3600Export() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .cmx3600EDL).export(context: context, to: dir)
        #expect(FileManager.default.fileExists(atPath: artifact.filePath))
        #expect(artifact.byteCount > 0)
    }

    @Test("CMX 3600 EDL file starts with TITLE: or FCM:")
    func cmx3600StartsWithHeader() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .cmx3600EDL).export(context: context, to: dir)
        let contents = try String(contentsOfFile: artifact.filePath, encoding: .utf8)
        let firstLine = contents.components(separatedBy: .newlines).first ?? ""
        #expect(firstLine.hasPrefix("TITLE:") || firstLine.hasPrefix("FCM:"))
    }

    @Test("Premiere XML export produces a non-empty file")
    func premiereXMLExport() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .premiereXML).export(context: context, to: dir)
        #expect(FileManager.default.fileExists(atPath: artifact.filePath))
        #expect(artifact.byteCount > 0)
    }

    @Test("DaVinci Resolve XML export produces a non-empty file")
    func davinciResolveXMLExport() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .davinciResolveXML).export(context: context, to: dir)
        #expect(FileManager.default.fileExists(atPath: artifact.filePath))
        #expect(artifact.byteCount > 0)
    }

    @Test("Assembly Archive export produces a non-empty JSON file")
    func assemblyArchiveExport() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let artifact = try ExportWriterFactory.writer(for: .assemblyArchive).export(context: context, to: dir)
        #expect(FileManager.default.fileExists(atPath: artifact.filePath))
        #expect(artifact.byteCount > 0)

        // Archive exports are JSON — must be valid UTF-8
        let contents = try String(contentsOfFile: artifact.filePath, encoding: .utf8)
        #expect(!contents.isEmpty)
    }

    @Test("AAF export produces a non-empty file (or throws externalToolUnavailable)")
    func aafExport() async throws {
        let context = try await makeContext()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        do {
            let artifact = try ExportWriterFactory.writer(for: .aaf).export(context: context, to: dir)
            #expect(FileManager.default.fileExists(atPath: artifact.filePath))
            #expect(artifact.byteCount > 0)
        } catch ExportWriterError.externalToolUnavailable {
            // Acceptable in CI — pyaaf2 bridge may not be present
        } catch ExportWriterError.externalToolFailed {
            // Also acceptable — pyaaf2 present but environment lacks media paths
        }
    }
}

// MARK: - Suite: ExportFormat metadata

@Suite("ExportFormat metadata")
struct ExportFormatMetadataTests {

    @Test("All formats have non-empty fileExtension")
    func fileExtensionNonEmpty() {
        for format in ExportFormat.allCases {
            #expect(!format.fileExtension.isEmpty)
        }
    }

    @Test("All formats have non-empty displayName")
    func displayNameNonEmpty() {
        for format in ExportFormat.allCases {
            #expect(!format.displayName.isEmpty)
        }
    }

    @Test("fileExtension spot-check: fcpxml → fcpxml, cmx3600EDL → edl, aaf → aaf")
    func fileExtensionValues() {
        #expect(ExportFormat.fcpxml.fileExtension        == "fcpxml")
        #expect(ExportFormat.cmx3600EDL.fileExtension    == "edl")
        #expect(ExportFormat.aaf.fileExtension           == "aaf")
        #expect(ExportFormat.premiereXML.fileExtension   == "xml")
        #expect(ExportFormat.davinciResolveXML.fileExtension == "xml")
    }

    @Test("ExportWriterFactory vends a writer for every format")
    func factoryCoversAllFormats() {
        for format in ExportFormat.allCases {
            let writer = ExportWriterFactory.writer(for: format)
            #expect(writer.format == format)
        }
    }
}
