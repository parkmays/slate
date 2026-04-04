import ExportWriters
import Foundation
import GRDB
import SLATESharedTypes

public struct AssemblyVersionRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var assemblyId: String
    public var projectId: String
    public var version: Int
    public var format: ExportFormat
    public var exportedAt: String
    public var exportedBy: String
    public var artifactPath: String
    public var assembly: Assembly

    public init(
        id: String = UUID().uuidString,
        assemblyId: String,
        projectId: String,
        version: Int,
        format: ExportFormat,
        exportedAt: String = ISO8601DateFormatter().string(from: Date()),
        exportedBy: String,
        artifactPath: String,
        assembly: Assembly
    ) {
        self.id = id
        self.assemblyId = assemblyId
        self.projectId = projectId
        self.version = version
        self.format = format
        self.exportedAt = exportedAt
        self.exportedBy = exportedBy
        self.artifactPath = artifactPath
        self.assembly = assembly
    }
}

public enum AssemblyStoreError: Error, LocalizedError {
    case databaseUnavailable
    case noAssemblyLoaded
    case noDeliveryTargets

    public var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "The assembly database is not available yet."
        case .noAssemblyLoaded:
            return "Generate or select an assembly before editing or exporting."
        case .noDeliveryTargets:
            return "No delivery targets configured for this project."
        }
    }
}

@MainActor
public final class AssemblyStore: ObservableObject {
    @Published public private(set) var assemblies: [Assembly] = []
    @Published public private(set) var versions: [AssemblyVersionRecord] = []
    @Published public private(set) var currentAssembly: Assembly?
    @Published public private(set) var lastExportArtifact: ExportArtifact?
    @Published public private(set) var loading = false
    @Published public var error: Error?

    private let dbPath: String
    private let engine = AssemblyEngine()
    private var dbQueue: DatabaseQueue?
    private var selectedProjectId: String?
    private var selectedProjectName: String?

    public init(dbPath: String = GRDBClipStore.defaultDBPath()) {
        self.dbPath = dbPath
    }

    public func load(project: Project) async {
        loading = true
        error = nil

        do {
            try openDatabaseIfNeeded()
            selectedProjectId = project.id
            selectedProjectName = project.name
            assemblies = try loadAssemblies(projectId: project.id)
            currentAssembly = assemblies.first
            if let currentAssembly {
                versions = try loadVersions(assemblyId: currentAssembly.id)
            } else {
                versions = []
            }
        } catch {
            self.error = error
            assemblies = []
            versions = []
            currentAssembly = nil
        }

        loading = false
    }

    public func generateAssembly(
        project: Project,
        clips: [Clip],
        options: AssemblyGenerationOptions
    ) async throws {
        try openDatabaseIfNeeded()

        let existingAssembly = assemblies.first { $0.name == resolvedName(project: project, options: options) }
        var effectiveOptions = options
        if effectiveOptions.preferredClipOrder.isEmpty {
            effectiveOptions.preferredClipOrder = existingAssembly?.clips.map(\.clipId) ?? currentAssembly?.clips.map(\.clipId) ?? []
        }

        let assembly = engine.buildAssembly(
            project: project,
            clips: clips,
            options: effectiveOptions,
            assemblyId: existingAssembly?.id ?? UUID().uuidString,
            version: existingAssembly?.version ?? 1
        )

        try saveAssembly(assembly)
        assemblies = try loadAssemblies(projectId: project.id)
        currentAssembly = assemblies.first(where: { $0.id == assembly.id }) ?? assembly
        versions = try loadVersions(assemblyId: assembly.id)
    }

    public func selectAssembly(_ assembly: Assembly) async throws {
        try openDatabaseIfNeeded()
        currentAssembly = assembly
        versions = try loadVersions(assemblyId: assembly.id)
    }

    public func recallVersion(_ version: AssemblyVersionRecord) async throws {
        try openDatabaseIfNeeded()
        currentAssembly = version.assembly
        try saveAssembly(version.assembly)
        versions = try loadVersions(assemblyId: version.assemblyId)
    }

    public func renameCurrentAssembly(_ name: String) throws {
        guard var assembly = currentAssembly else {
            throw AssemblyStoreError.noAssemblyLoaded
        }

        assembly.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try persistCurrentAssembly(assembly)
    }

    public func moveCurrentAssemblyClips(fromOffsets: IndexSet, toOffset: Int) throws {
        guard var assembly = currentAssembly else {
            throw AssemblyStoreError.noAssemblyLoaded
        }

        Self.move(&assembly.clips, fromOffsets: fromOffsets, toOffset: toOffset)
        try persistCurrentAssembly(assembly)
    }

    public func updateTrim(for clipId: String, inPoint: Double, outPoint: Double) throws {
        guard var assembly = currentAssembly else {
            throw AssemblyStoreError.noAssemblyLoaded
        }

        guard let index = assembly.clips.firstIndex(where: { $0.clipId == clipId }) else {
            return
        }

        let safeInPoint = max(0, min(inPoint, outPoint))
        let safeOutPoint = max(safeInPoint, outPoint)
        assembly.clips[index].inPoint = safeInPoint
        assembly.clips[index].outPoint = safeOutPoint
        try persistCurrentAssembly(assembly)
    }

    public func exportCurrentAssembly(
        clips: [Clip],
        format: ExportFormat = .assemblyArchive,
        exportedBy: String = "Current User",
        outputDirectory: URL? = nil
    ) async throws -> ExportArtifact {
        try openDatabaseIfNeeded()

        guard var assembly = currentAssembly else {
            throw AssemblyStoreError.noAssemblyLoaded
        }

        let nextVersion = (versions.map(\.version).max() ?? 0) + 1
        assembly.version = max(nextVersion, assembly.version)

        let writer = ExportWriterFactory.writer(for: format)
        let clipLookup = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let artifact = try writer.export(
            context: ExportContext(
                assembly: assembly,
                clipsById: clipLookup,
                projectName: selectedProjectName
            ),
            to: outputDirectory ?? Self.defaultExportDirectory(projectId: assembly.projectId)
        )

        let versionRecord = AssemblyVersionRecord(
            assemblyId: assembly.id,
            projectId: assembly.projectId,
            version: assembly.version,
            format: format,
            exportedBy: exportedBy,
            artifactPath: artifact.filePath,
            assembly: assembly
        )

        try saveAssembly(assembly)
        try saveVersion(versionRecord)

        if let projectId = selectedProjectId {
            assemblies = try loadAssemblies(projectId: projectId)
        }
        versions = try loadVersions(assemblyId: assembly.id)
        currentAssembly = assembly
        lastExportArtifact = artifact
        return artifact
    }
    
    public func deliver(project: Project, shareURL: URL) async throws {
        guard !project.notificationTargets.isEmpty else {
            throw AssemblyStoreError.noDeliveryTargets
        }
        
        await NotificationService.shared.deliver(
            projectName: project.name,
            shareURL: shareURL,
            targets: project.notificationTargets
        )
    }

    public static func defaultExportDirectory(projectId: String) -> URL {
        let baseDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("SLATE Exports", isDirectory: true)
            .appendingPathComponent(projectId, isDirectory: true)
    }

    private func persistCurrentAssembly(_ assembly: Assembly) throws {
        try saveAssembly(assembly)
        currentAssembly = assembly
        if let projectId = selectedProjectId {
            assemblies = try loadAssemblies(projectId: projectId)
        }
    }

    private func resolvedName(project: Project, options: AssemblyGenerationOptions) -> String {
        engine.buildAssembly(project: project, clips: [], options: options).name
    }

    private func openDatabaseIfNeeded() throws {
        if dbQueue != nil {
            return
        }

        let url = URL(fileURLWithPath: dbPath)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let queue = try DatabaseQueue(path: dbPath)
        try queue.write { db in
            try Self.ensureAssemblySchema(in: db)
        }
        dbQueue = queue
    }

    private func saveAssembly(_ assembly: Assembly) throws {
        guard let dbQueue else {
            throw AssemblyStoreError.databaseUnavailable
        }

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO assemblies (id, project_id, name, mode, clips, created_at, version)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        project_id = excluded.project_id,
                        name = excluded.name,
                        mode = excluded.mode,
                        clips = excluded.clips,
                        created_at = excluded.created_at,
                        version = excluded.version
                """,
                arguments: try [
                    assembly.id,
                    assembly.projectId,
                    assembly.name,
                    assembly.mode.rawValue,
                    Self.encodeJSON(assembly.clips) ?? "[]",
                    assembly.createdAt,
                    assembly.version
                ]
            )
        }
    }

    private func saveVersion(_ record: AssemblyVersionRecord) throws {
        guard let dbQueue else {
            throw AssemblyStoreError.databaseUnavailable
        }

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO assembly_versions (
                        id, assembly_id, project_id, version, format,
                        exported_at, exported_by, artifact_path, assembly_json
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: try [
                    record.id,
                    record.assemblyId,
                    record.projectId,
                    record.version,
                    record.format.rawValue,
                    record.exportedAt,
                    record.exportedBy,
                    record.artifactPath,
                    Self.encodeJSON(record.assembly) ?? "{}"
                ]
            )
        }
    }

    private func loadAssemblies(projectId: String) throws -> [Assembly] {
        guard let dbQueue else {
            throw AssemblyStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM assemblies
                    WHERE project_id = ?
                    ORDER BY version DESC, created_at DESC
                """,
                arguments: [projectId]
            )
            return try rows.map(Self.decodeAssembly(from:))
        }
    }

    private func loadVersions(assemblyId: String) throws -> [AssemblyVersionRecord] {
        guard let dbQueue else {
            throw AssemblyStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM assembly_versions
                    WHERE assembly_id = ?
                    ORDER BY version DESC, exported_at DESC
                """,
                arguments: [assemblyId]
            )
            return try rows.map(Self.decodeVersion(from:))
        }
    }

    nonisolated static func ensureAssemblySchema(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS assemblies (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                mode TEXT NOT NULL,
                clips TEXT NOT NULL DEFAULT '[]',
                created_at TEXT NOT NULL,
                version INTEGER NOT NULL DEFAULT 1
            )
        """)

        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS assembly_versions (
                id TEXT PRIMARY KEY NOT NULL,
                assembly_id TEXT NOT NULL,
                project_id TEXT NOT NULL,
                version INTEGER NOT NULL,
                format TEXT NOT NULL,
                exported_at TEXT NOT NULL,
                exported_by TEXT NOT NULL,
                artifact_path TEXT NOT NULL,
                assembly_json TEXT NOT NULL
            )
        """)

        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_assemblies_project_id ON assemblies(project_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_assembly_versions_assembly_id ON assembly_versions(assembly_id)")
    }

    private static func decodeAssembly(from row: Row) throws -> Assembly {
        Assembly(
            id: row["id"],
            projectId: row["project_id"],
            name: row["name"],
            mode: ProjectMode(rawValue: row["mode"]) ?? .narrative,
            clips: try decodeJSON(row["clips"], as: [AssemblyClip].self) ?? [],
            createdAt: row["created_at"],
            version: row["version"]
        )
    }

    private static func decodeVersion(from row: Row) throws -> AssemblyVersionRecord {
        AssemblyVersionRecord(
            id: row["id"],
            assemblyId: row["assembly_id"],
            projectId: row["project_id"],
            version: row["version"],
            format: ExportFormat(rawValue: row["format"]) ?? .assemblyArchive,
            exportedAt: row["exported_at"],
            exportedBy: row["exported_by"],
            artifactPath: row["artifact_path"],
            assembly: try decodeJSON(row["assembly_json"], as: Assembly.self) ?? Assembly(
                id: row["assembly_id"],
                projectId: row["project_id"],
                name: "Recovered Assembly",
                mode: .narrative
            )
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else {
            return nil
        }

        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)
    }

    private static func decodeJSON<T: Decodable>(_ payload: String?, as type: T.Type) throws -> T? {
        guard let payload, !payload.isEmpty else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
    }

    private static func move<T>(_ array: inout [T], fromOffsets: IndexSet, toOffset: Int) {
        let moved = fromOffsets.map { array[$0] }
        let removalCountBeforeDestination = fromOffsets.filter { $0 < toOffset }.count
        for index in fromOffsets.sorted(by: >) {
            array.remove(at: index)
        }
        array.insert(contentsOf: moved, at: toOffset - removalCountBeforeDestination)
    }
}
