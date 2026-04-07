// SLATE — GRDBClipStore
// Owned by: Claude Code
//
// Desktop-side read-mostly store for the canonical SQLite database shared with
// the ingest daemon.

import Combine
import Foundation
import GRDB
import IngestDaemon
import SLATESharedTypes
import SwiftUI

public struct ProjectStatistics: Sendable {
    public var totalClips: Int
    public var reviewProgress: Double
    public var proxyProgress: Double

    public static let empty = ProjectStatistics(totalClips: 0, reviewProgress: 0, proxyProgress: 0)
}

@MainActor
public final class GRDBClipStore: ObservableObject {
    @Published public private(set) var clips: [Clip] = []
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var loading = true
    @Published public private(set) var statistics = ProjectStatistics.empty
    @Published public var error: Error?

    private let dbPath: String
    private var dbQueue: DatabaseQueue?
    private var selectedProjectId: String?

    public init(dbPath: String = GRDBClipStore.defaultDBPath()) {
        self.dbPath = dbPath
        Task { await openDatabase() }
    }

    public static func defaultDBPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let slateDirectory = appSupport.appendingPathComponent("SLATE", isDirectory: true)
        try? FileManager.default.createDirectory(at: slateDirectory, withIntermediateDirectories: true)
        return slateDirectory.appendingPathComponent("slate.db").path
    }

    public func selectProject(_ project: Project) async {
        selectedProjectId = project.id
        await loadClips()
    }

    public func loadClips() async {
        guard let dbQueue else {
            return
        }

        guard let selectedProjectId else {
            clips = []
            statistics = .empty
            return
        }

        do {
            let rows = try await dbQueue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM clips
                        WHERE project_id = ?
                        ORDER BY updated_at DESC, ingested_at DESC
                    """,
                    arguments: [selectedProjectId]
                )
            }
            clips = try rows.map(Self.decodeClip(from:))
            statistics = Self.makeStatistics(from: clips)
        } catch {
            self.error = error
            clips = []
            statistics = .empty
        }
    }

    public func reloadCurrentProject() async {
        await loadProjects()
        await loadClips()
    }

    public func statistics(for projectId: String) -> ProjectStatistics {
        guard projectId == selectedProjectId else {
            return .empty
        }
        return statistics
    }

    /// Latest merged project row (including UserDefaults delivery settings).
    public func project(byId id: String) -> Project? {
        projects.first(where: { $0.id == id })
    }

    /// All clips for a project (not limited to the selected sidebar project).
    public func fetchAllClips(forProjectId projectId: String) async -> [Clip] {
        guard let dbQueue else {
            return []
        }
        do {
            let rows = try await dbQueue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM clips
                        WHERE project_id = ?
                        ORDER BY ingested_at DESC
                    """,
                    arguments: [projectId]
                )
            }
            return try rows.map(Self.decodeClip(from:))
        } catch {
            self.error = error
            return []
        }
    }

    /// Updates in-memory `projects` after changing delivery / digest settings.
    public func applyDeliverySettings(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        }
    }

    public var groupedNarrativeClips: [String: [Clip]] {
        Dictionary(grouping: clips) { clip in
            clip.narrativeMeta?.sceneNumber.isEmpty == false ? clip.narrativeMeta!.sceneNumber : "Unknown Scene"
        }
    }

    public var groupedDocumentaryClips: [String: [Clip]] {
        Dictionary(grouping: clips) { clip in
            clip.documentaryMeta?.subjectName.isEmpty == false ? clip.documentaryMeta!.subjectName : "Unknown Subject"
        }
    }

    private func openDatabase() async {
        do {
            let queue = try DatabaseQueue(path: dbPath)
            dbQueue = queue
            try await ensureSchema(on: queue)
            await loadProjects()
            await loadClips()
        } catch {
            self.error = error
            self.loading = false
        }
    }

    private func loadProjects() async {
        guard let dbQueue else {
            return
        }

        do {
            let rows = try await dbQueue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM projects
                        ORDER BY updated_at DESC, created_at DESC
                    """
                )
            }
            projects = rows.compactMap { row in
                guard let base = Self.decodeProject(from: row) else { return nil }
                return ProjectSettingsPersistence.merge(into: base)
            }
            if selectedProjectId == nil {
                selectedProjectId = projects.first?.id
            }
            loading = false
        } catch {
            self.error = error
            projects = []
            loading = false
        }
    }

    private func ensureSchema(on dbQueue: DatabaseQueue) async throws {
        try await dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
            """)
            try Self.migrateProjectsColumnsIfNeeded(in: db)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clips (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL,
                    checksum TEXT NOT NULL,
                    source_path TEXT NOT NULL,
                    source_size INTEGER NOT NULL,
                    source_format TEXT NOT NULL,
                    source_fps REAL NOT NULL,
                    source_timecode_start TEXT NOT NULL,
                    duration REAL NOT NULL,
                    proxy_path TEXT,
                    proxy_status TEXT NOT NULL,
                    proxy_checksum TEXT,
                    narrative_meta TEXT,
                    documentary_meta TEXT,
                    audio_tracks TEXT NOT NULL DEFAULT '[]',
                    sync_result TEXT NOT NULL DEFAULT '{}',
                    synced_audio_path TEXT,
                    ai_scores TEXT,
                    transcript_id TEXT,
                    ai_processing_status TEXT NOT NULL DEFAULT 'pending',
                    review_status TEXT NOT NULL DEFAULT 'unreviewed',
                    annotations TEXT NOT NULL DEFAULT '[]',
                    approval_status TEXT NOT NULL DEFAULT 'pending',
                    approved_by TEXT,
                    approved_at TEXT,
                    ingested_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    project_mode TEXT NOT NULL
                )
            """)
            try AssemblyStore.ensureAssemblySchema(in: db)
            try Self.migrateClipsColumnsIfNeeded(in: db)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS scripts (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                    title TEXT,
                    total_pages INTEGER NOT NULL,
                    scenes TEXT NOT NULL,
                    source_filename TEXT,
                    parsed_at TEXT NOT NULL
                )
            """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS clip_script_mappings (
                    clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
                    script_id TEXT NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
                    scene_number TEXT NOT NULL,
                    confidence REAL NOT NULL,
                    mapping_source TEXT NOT NULL,
                    PRIMARY KEY (clip_id, script_id)
                )
            """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_scripts_project_id ON scripts(project_id)")
        }
    }

    /// Imports a `.fdx` or `.pdf` screenplay into the local GRDB database and maps clips for the project.
    public func importScript(from url: URL, projectId: String) async throws -> ScriptImportResult {
        guard let dbQueue else {
            throw NSError(
                domain: "GRDBClipStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Database is not open."]
            )
        }
        let result: ScriptImportResult
        switch url.pathExtension.lowercased() {
        case "fdx":
            result = try ScriptImporter.parse(fdxURL: url)
        case "pdf":
            result = try ScriptImporter.parse(pdfURL: url)
        default:
            throw NSError(
                domain: "GRDBClipStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Choose a .fdx or .pdf screenplay."]
            )
        }

        let rows = try await dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM clips WHERE project_id = ?",
                arguments: [projectId]
            )
        }
        let projectClips = try rows.map { try Self.decodeClip(from: $0) }
        let mappings = ScriptImporter.mapClipsToScript(clips: projectClips, script: result)
        let scriptId = UUID().uuidString
        let scenesData = try JSONEncoder().encode(result.scenes)
        let scenesJSON = String(data: scenesData, encoding: .utf8) ?? "[]"

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO scripts (id, project_id, title, total_pages, scenes, source_filename, parsed_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    scriptId,
                    projectId,
                    result.title,
                    result.totalPages,
                    scenesJSON,
                    url.lastPathComponent,
                    result.parsedAt
                ]
            )
            for m in mappings {
                try db.execute(
                    sql: """
                        INSERT INTO clip_script_mappings (clip_id, script_id, scene_number, confidence, mapping_source)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        m.clipId,
                        scriptId,
                        m.sceneNumber,
                        m.confidence,
                        m.source.rawValue
                    ]
                )
            }
        }

        if selectedProjectId == projectId {
            await loadClips()
        }
        return result
    }

    /// Clips sharing a multi-camera group id, ordered A → D by `cameraAngle`.
    public func clips(forGroupId groupId: String) -> [Clip] {
        clips
            .filter { $0.cameraGroupId == groupId }
            .sorted { lhs, rhs in
                Self.angleSortKey(lhs.cameraAngle) < Self.angleSortKey(rhs.cameraAngle)
            }
    }

    private static func angleSortKey(_ angle: String?) -> Int {
        guard let raw = angle?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !raw.isEmpty else {
            return 99
        }
        let letter = raw.prefix(1)
        switch letter {
        case "A": return 0
        case "B": return 1
        case "C": return 2
        case "D": return 3
        default: return 99
        }
    }

    public func hasMultipleAngles(forGroupId groupId: String) -> Bool {
        clips(forGroupId: groupId).count >= 2
    }

    public func updateReviewStatus(clipId: String, status: ReviewStatus) async {
        guard let dbQueue, let selectedProjectId else {
            return
        }
        let now = ISO8601DateFormatter().string(from: Date())
        do {
            try await dbQueue.write { db in
                try db.execute(
                    sql: """
                        UPDATE clips
                        SET review_status = ?, updated_at = ?
                        WHERE id = ? AND project_id = ?
                    """,
                    arguments: [status.rawValue, now, clipId, selectedProjectId]
                )
            }
            await loadClips()
            NotificationCenter.default.post(name: .clipUpdated, object: nil)
        } catch {
            self.error = error
        }
    }

    /// Circles one clip in a multi-cam group and clears circle status on sibling angles.
    public func applyCircleInMultiCamGroup(selectedClipId: String, groupId: String) async {
        let siblings = clips(forGroupId: groupId)
        guard siblings.contains(where: { $0.id == selectedClipId }) else {
            return
        }
        guard let dbQueue, let selectedProjectId else {
            return
        }
        let now = ISO8601DateFormatter().string(from: Date())
        do {
            try await dbQueue.write { db in
                for clip in siblings {
                    let status: ReviewStatus = clip.id == selectedClipId ? .circled : .unreviewed
                    try db.execute(
                        sql: """
                            UPDATE clips
                            SET review_status = ?, updated_at = ?
                            WHERE id = ? AND project_id = ?
                        """,
                        arguments: [status.rawValue, now, clip.id, selectedProjectId]
                    )
                }
            }
            await loadClips()
            NotificationCenter.default.post(name: .clipUpdated, object: nil)
        } catch {
            self.error = error
        }
    }

    private nonisolated static func migrateProjectsColumnsIfNeeded(in db: Database) throws {
        let columns = try String.fetchAll(
            db,
            sql: "SELECT name FROM pragma_table_info('projects')"
        )
        func addColumn(_ sql: String) throws {
            try db.execute(sql: sql)
        }
        if !columns.contains("airtable_api_key") {
            try addColumn("ALTER TABLE projects ADD COLUMN airtable_api_key TEXT")
        }
        if !columns.contains("airtable_base_id") {
            try addColumn("ALTER TABLE projects ADD COLUMN airtable_base_id TEXT")
        }
        if !columns.contains("shotgrid_script_name") {
            try addColumn("ALTER TABLE projects ADD COLUMN shotgrid_script_name TEXT")
        }
        if !columns.contains("shotgrid_application_key") {
            try addColumn("ALTER TABLE projects ADD COLUMN shotgrid_application_key TEXT")
        }
        if !columns.contains("shotgrid_site") {
            try addColumn("ALTER TABLE projects ADD COLUMN shotgrid_site TEXT")
        }
    }

    private nonisolated static func migrateClipsColumnsIfNeeded(in db: Database) throws {
        let columns = try String.fetchAll(
            db,
            sql: "SELECT name FROM pragma_table_info('clips')"
        )
        func addColumn(_ sql: String) throws {
            try db.execute(sql: sql)
        }
        if !columns.contains("camera_group_id") {
            try addColumn("ALTER TABLE clips ADD COLUMN camera_group_id TEXT")
        }
        if !columns.contains("camera_angle") {
            try addColumn("ALTER TABLE clips ADD COLUMN camera_angle TEXT")
        }
        if !columns.contains("proxy_lut") {
            try addColumn("ALTER TABLE clips ADD COLUMN proxy_lut TEXT")
        }
        if !columns.contains("proxy_color_space") {
            try addColumn("ALTER TABLE clips ADD COLUMN proxy_color_space TEXT")
        }
        if !columns.contains("camera_metadata") {
            try addColumn("ALTER TABLE clips ADD COLUMN camera_metadata TEXT")
        }
        if !columns.contains("proxy_r2_url") {
            try addColumn("ALTER TABLE clips ADD COLUMN proxy_r2_url TEXT")
        }
        if !columns.contains("proxy_r2_uploaded_at") {
            try addColumn("ALTER TABLE clips ADD COLUMN proxy_r2_uploaded_at TEXT")
        }
        if !columns.contains("airtable_record_id") {
            try addColumn("ALTER TABLE clips ADD COLUMN airtable_record_id TEXT")
        }
        if !columns.contains("shotgrid_entity_id") {
            try addColumn("ALTER TABLE clips ADD COLUMN shotgrid_entity_id TEXT")
        }
        if !columns.contains("editorial_updated_at") {
            try addColumn("ALTER TABLE clips ADD COLUMN editorial_updated_at TEXT")
        }
        if !columns.contains("custom_proxy_lut_path") {
            try addColumn("ALTER TABLE clips ADD COLUMN custom_proxy_lut_path TEXT")
        }
    }

    private static func makeStatistics(from clips: [Clip]) -> ProjectStatistics {
        let totalClips = clips.count
        guard totalClips > 0 else {
            return .empty
        }

        let reviewedCount = clips.filter { $0.reviewStatus != .unreviewed }.count
        let readyProxies = clips.filter { [.ready, .completed].contains($0.proxyStatus) }.count

        return ProjectStatistics(
            totalClips: totalClips,
            reviewProgress: Double(reviewedCount) / Double(totalClips),
            proxyProgress: Double(readyProxies) / Double(totalClips)
        )
    }

    private static func decodeProject(from row: Row) -> Project? {
        guard let mode = ProjectMode(rawValue: row["mode"]) else {
            return nil
        }

        return Project(
            id: row["id"],
            name: row["name"],
            mode: mode,
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            airtableAPIKey: row["airtable_api_key"],
            airtableBaseId: row["airtable_base_id"],
            shotgridScriptName: row["shotgrid_script_name"],
            shotgridApplicationKey: row["shotgrid_application_key"],
            shotgridSite: row["shotgrid_site"]
        )
    }

    private static func decodeClip(from row: Row) throws -> Clip {
        Clip(
            id: row["id"],
            projectId: row["project_id"],
            checksum: row["checksum"],
            sourcePath: row["source_path"],
            sourceSize: row["source_size"],
            sourceFormat: SourceFormat(rawValue: row["source_format"]) ?? .h264,
            sourceFps: row["source_fps"],
            sourceTimecodeStart: row["source_timecode_start"],
            duration: row["duration"],
            proxyPath: row["proxy_path"],
            proxyStatus: ProxyStatus(rawValue: row["proxy_status"]) ?? .pending,
            proxyChecksum: row["proxy_checksum"],
            proxyR2URL: row["proxy_r2_url"],
            proxyLUT: row["proxy_lut"],
            proxyColorSpace: row["proxy_color_space"],
            narrativeMeta: try decodeJSON(row["narrative_meta"], as: NarrativeMeta.self),
            documentaryMeta: try decodeJSON(row["documentary_meta"], as: DocumentaryMeta.self),
            audioTracks: try decodeJSON(row["audio_tracks"], as: [AudioTrack].self) ?? [],
            syncResult: try decodeJSON(row["sync_result"], as: SyncResult.self) ?? .unsynced,
            syncedAudioPath: row["synced_audio_path"],
            cameraGroupId: row["camera_group_id"],
            cameraAngle: row["camera_angle"],
            aiScores: try decodeJSON(row["ai_scores"], as: AIScores.self),
            transcriptId: row["transcript_id"],
            aiProcessingStatus: AIProcessingStatus(rawValue: row["ai_processing_status"]) ?? .pending,
            reviewStatus: ReviewStatus(rawValue: row["review_status"]) ?? .unreviewed,
            annotations: try decodeJSON(row["annotations"], as: [Annotation].self) ?? [],
            approvalStatus: ApprovalStatus(rawValue: row["approval_status"]) ?? .pending,
            approvedBy: row["approved_by"],
            approvedAt: row["approved_at"],
            ingestedAt: row["ingested_at"],
            updatedAt: row["updated_at"],
            projectMode: ProjectMode(rawValue: row["project_mode"]) ?? .narrative,
            cameraMetadata: try decodeJSON(row["camera_metadata"], as: CameraMetadata.self),
            airtableRecordId: row["airtable_record_id"],
            shotgridEntityId: row["shotgrid_entity_id"],
            editorialUpdatedAt: row["editorial_updated_at"],
            customProxyLUTPath: row["custom_proxy_lut_path"]
        )
    }

    private static func decodeJSON<T: Decodable>(_ payload: String?, as type: T.Type) throws -> T? {
        guard let payload, !payload.isEmpty else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
    }
}
