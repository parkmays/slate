// SLATE — GRDBStore (Daemon-side canonical store)
// Owned by: Claude Code
//
// Single actor wrapping the shared SQLite DB at
// ~/Library/Application Support/SLATE/slate.db
//
// RULE: Only the daemon WRITES to this database.
//       The desktop reads via GRDBClipStore (read-only).
// RULE: Complex types stored as JSON TEXT blobs:
//       sync_result, ai_scores, audio_tracks, annotations,
//       narrative_meta, documentary_meta.

import Foundation
import GRDB
import SLATEAIPipeline
import SLATESharedTypes

public enum GRDBStoreError: Error, LocalizedError {
    case notSetup
    case encodingFailed(String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notSetup:
            return "GRDBStore.setup(at:) has not been called"
        case .encodingFailed(let message):
            return "JSON encoding failed: \(message)"
        case .decodingFailed(let message):
            return "JSON decoding failed: \(message)"
        }
    }
}

public actor GRDBStore {
    public static let shared = GRDBStore()

    private var databaseQueue: DatabaseQueue?

    public init() {}

    public init(path: String) throws {
        let queue = try Self.makeQueue(path: path)
        self.databaseQueue = queue
        try queue.write { db in
            try Self.buildSchema(in: db)
        }
    }

    public func setup(at path: String) throws {
        if databaseQueue != nil {
            return
        }

        let queue = try Self.makeQueue(path: path)
        try queue.write { db in
            try Self.buildSchema(in: db)
        }
        databaseQueue = queue
    }

    public func saveProject(_ project: Project) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO projects (
                        id, name, mode, created_at, updated_at,
                        airtable_api_key, airtable_base_id, shotgrid_script_name, shotgrid_application_key,
                        shotgrid_site
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        mode = excluded.mode,
                        created_at = excluded.created_at,
                        updated_at = excluded.updated_at,
                        airtable_api_key = COALESCE(excluded.airtable_api_key, projects.airtable_api_key),
                        airtable_base_id = COALESCE(excluded.airtable_base_id, projects.airtable_base_id),
                        shotgrid_script_name = COALESCE(excluded.shotgrid_script_name, projects.shotgrid_script_name),
                        shotgrid_application_key = COALESCE(excluded.shotgrid_application_key, projects.shotgrid_application_key),
                        shotgrid_site = COALESCE(excluded.shotgrid_site, projects.shotgrid_site)
                """,
                arguments: [
                    project.id,
                    project.name,
                    project.mode.rawValue,
                    project.createdAt,
                    project.updatedAt,
                    project.airtableAPIKey,
                    project.airtableBaseId,
                    project.shotgridScriptName,
                    project.shotgridApplicationKey,
                    project.shotgridSite
                ]
            )
        }
    }

    public func saveClip(_ clip: Clip) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clips (
                        id, project_id, checksum, source_path, source_size, source_format,
                        source_fps, source_timecode_start, duration, proxy_path, proxy_status,
                        proxy_checksum, proxy_lut, proxy_color_space,
                        narrative_meta, documentary_meta, audio_tracks,
                        sync_result, synced_audio_path, camera_group_id, camera_angle,
                        ai_scores, transcript_id,
                        ai_processing_status, review_status, annotations, approval_status,
                        approved_by, approved_at, ingested_at, updated_at, project_mode, camera_metadata,
                        proxy_r2_url, proxy_r2_uploaded_at,
                        airtable_record_id, shotgrid_entity_id, editorial_updated_at,
                        custom_proxy_lut_path
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        project_id = excluded.project_id,
                        checksum = excluded.checksum,
                        source_path = excluded.source_path,
                        source_size = excluded.source_size,
                        source_format = excluded.source_format,
                        source_fps = excluded.source_fps,
                        source_timecode_start = excluded.source_timecode_start,
                        duration = excluded.duration,
                        proxy_path = excluded.proxy_path,
                        proxy_status = excluded.proxy_status,
                        proxy_checksum = excluded.proxy_checksum,
                        proxy_lut = excluded.proxy_lut,
                        proxy_color_space = excluded.proxy_color_space,
                        narrative_meta = excluded.narrative_meta,
                        documentary_meta = excluded.documentary_meta,
                        audio_tracks = excluded.audio_tracks,
                        sync_result = excluded.sync_result,
                        synced_audio_path = excluded.synced_audio_path,
                        camera_group_id = excluded.camera_group_id,
                        camera_angle = excluded.camera_angle,
                        ai_scores = excluded.ai_scores,
                        transcript_id = excluded.transcript_id,
                        ai_processing_status = excluded.ai_processing_status,
                        review_status = excluded.review_status,
                        annotations = excluded.annotations,
                        approval_status = excluded.approval_status,
                        approved_by = excluded.approved_by,
                        approved_at = excluded.approved_at,
                        ingested_at = excluded.ingested_at,
                        updated_at = excluded.updated_at,
                        project_mode = excluded.project_mode,
                        camera_metadata = excluded.camera_metadata,
                        proxy_r2_url = excluded.proxy_r2_url,
                        proxy_r2_uploaded_at = excluded.proxy_r2_uploaded_at,
                        airtable_record_id = excluded.airtable_record_id,
                        shotgrid_entity_id = excluded.shotgrid_entity_id,
                        editorial_updated_at = excluded.editorial_updated_at,
                        custom_proxy_lut_path = excluded.custom_proxy_lut_path
                """,
                arguments: try [
                    clip.id,
                    clip.projectId,
                    clip.checksum,
                    clip.sourcePath,
                    clip.sourceSize,
                    clip.sourceFormat.rawValue,
                    clip.sourceFps,
                    clip.sourceTimecodeStart,
                    clip.duration,
                    clip.proxyPath,
                    clip.proxyStatus.rawValue,
                    clip.proxyChecksum,
                    clip.proxyLUT,
                    clip.proxyColorSpace,
                    Self.encodeJSON(clip.narrativeMeta),
                    Self.encodeJSON(clip.documentaryMeta),
                    Self.encodeJSON(clip.audioTracks) ?? "[]",
                    Self.encodeJSON(clip.syncResult) ?? "{}",
                    clip.syncedAudioPath,
                    clip.cameraGroupId,
                    clip.cameraAngle,
                    Self.encodeJSON(clip.aiScores),
                    clip.transcriptId,
                    clip.aiProcessingStatus.rawValue,
                    clip.reviewStatus.rawValue,
                    Self.encodeJSON(clip.annotations) ?? "[]",
                    clip.approvalStatus.rawValue,
                    clip.approvedBy,
                    clip.approvedAt,
                    clip.ingestedAt,
                    clip.updatedAt,
                    clip.projectMode.rawValue,
                    Self.encodeJSON(clip.cameraMetadata),
                    clip.proxyR2URL,
                    nil as String?,
                    clip.airtableRecordId,
                    clip.shotgridEntityId,
                    clip.editorialUpdatedAt,
                    clip.customProxyLUTPath
                ]
            )
        }
    }

    /// Marks proxy as uploaded to R2 (Supabase parity: `proxy_status = completed`, public URL + timestamp).
    public func markProxyUploaded(clipId: String, publicURL: String) async throws {
        let queue = try q()
        let now = ISO8601DateFormatter().string(from: Date())
        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET proxy_status = ?,
                        proxy_r2_url = ?,
                        proxy_r2_uploaded_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    ProxyStatus.completed.rawValue,
                    publicURL,
                    now,
                    now,
                    clipId
                ]
            )
        }
    }

    public func getClip(byId clipId: String) async throws -> Clip? {
        let queue = try q()
        return try await queue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM clips WHERE id = ?",
                arguments: [clipId]
            )
            guard let row else {
                return nil
            }
            return try Self.decodeClip(from: row)
        }
    }

    public func getClip(byChecksum checksum: String) async throws -> Clip? {
        let queue = try q()
        return try await queue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM clips WHERE checksum = ? LIMIT 1",
                arguments: [checksum]
            )
            guard let row else {
                return nil
            }
            return try Self.decodeClip(from: row)
        }
    }

    /// Returns all clips sharing a camera group UUID. Used by IngestPipeline to build
    /// the full camera set for `syncCameraGroup()`.
    public func fetchClips(cameraGroupId: String) async throws -> [Clip] {
        let queue = try q()
        return try await queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM clips WHERE camera_group_id = ?",
                arguments: [cameraGroupId]
            )
            return try rows.map { try Self.decodeClip(from: $0) }
        }
    }

    /// Exposed so ProxyGenerator (and other callers in the same module) can access
    /// the underlying DatabaseQueue directly for GRDB `Column`-style updates.
    public var dbQueue: DatabaseQueue {
        get throws { try q() }
    }

    public func updateAudioSync(
        clipId: String,
        audioTracks: [AudioTrack],
        syncResult: SyncResult,
        syncedAudioPath: String?
    ) async throws {
        let queue = try q()
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET audio_tracks = ?, sync_result = ?, synced_audio_path = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: try [
                    Self.encodeJSON(audioTracks) ?? "[]",
                    Self.encodeJSON(syncResult) ?? "{}",
                    syncedAudioPath,
                    updatedAt,
                    clipId
                ]
            )
        }
    }

    public func updateAIProcessingStatus(
        clipId: String,
        status: AIProcessingStatus
    ) async throws {
        let queue = try q()
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET ai_processing_status = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: [status.rawValue, updatedAt, clipId]
            )
        }
    }

    public func updateClipAudioTracks(clipId: String, tracks: [AudioTrack]) async throws {
        let queue = try q()
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET audio_tracks = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: try [
                    Self.encodeJSON(tracks) ?? "[]",
                    updatedAt,
                    clipId
                ]
            )
        }
    }

    public func updateClipReviewStatus(clipId: String, status: ReviewStatus) async throws {
        let queue = try q()
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET review_status = ?, updated_at = ?, editorial_updated_at = ?
                    WHERE id = ?
                """,
                arguments: [status.rawValue, updatedAt, updatedAt, clipId]
            )
        }
    }

    public func updateAIScores(
        clipId: String,
        aiScores: AIScores,
        status: AIProcessingStatus
    ) async throws {
        let queue = try q()
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET ai_scores = ?, ai_processing_status = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: try [
                    Self.encodeJSON(aiScores),
                    status.rawValue,
                    updatedAt,
                    clipId
                ]
            )
        }
    }

    public func saveTranscript(_ transcript: Transcript, forClipId clipId: String) async throws {
        let queue = try q()
        let updatedAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE clips
                    SET transcript = ?, transcript_status = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: try [
                    Self.encodeJSON(transcript),
                    "complete",
                    updatedAt,
                    clipId
                ]
            )
        }
    }

    public func saveWatchFolder(_ watchFolder: WatchFolder) async throws {
        let queue = try q()
        let createdAt = ISO8601DateFormatter().string(from: Date())

        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO watch_folders (
                        path, project_id, mode, burn_in_config,
                        upload_throttle_bps, transcode_profile, offload_destinations, created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        project_id = excluded.project_id,
                        mode = excluded.mode,
                        burn_in_config = excluded.burn_in_config,
                        upload_throttle_bps = excluded.upload_throttle_bps,
                        transcode_profile = excluded.transcode_profile,
                        offload_destinations = excluded.offload_destinations
                """,
                arguments: [
                    watchFolder.path,
                    watchFolder.projectId,
                    watchFolder.mode.rawValue,
                    try Self.encodeJSON(watchFolder.burnInConfig),
                    watchFolder.uploadThrottleBytesPerSecond,
                    try Self.encodeJSON(watchFolder.transcodeProfile),
                    try Self.encodeJSON(watchFolder.offloadDestinations) ?? "[]",
                    createdAt
                ]
            )
        }
    }

    public func allWatchFolders() async throws -> [WatchFolder] {
        let queue = try q()
        return try await queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT path, project_id, mode, burn_in_config, upload_throttle_bps, transcode_profile, offload_destinations
                    FROM watch_folders
                    ORDER BY created_at ASC
                """
            )
            return rows.compactMap(Self.decodeWatchFolder(from:))
        }
    }

    private func q() throws -> DatabaseQueue {
        guard let databaseQueue else {
            throw GRDBStoreError.notSetup
        }
        return databaseQueue
    }

    private static func makeQueue(path: String) throws -> DatabaseQueue {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try DatabaseQueue(path: path)
    }

    private static func buildSchema(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                mode TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        let projectColumns = Set(try Row.fetchAll(db, sql: "PRAGMA table_info(projects)").compactMap { row in
            row["name"] as String?
        })
        if !projectColumns.contains("airtable_api_key") {
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN airtable_api_key TEXT")
        }
        if !projectColumns.contains("airtable_base_id") {
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN airtable_base_id TEXT")
        }
        if !projectColumns.contains("shotgrid_script_name") {
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN shotgrid_script_name TEXT")
        }
        if !projectColumns.contains("shotgrid_application_key") {
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN shotgrid_application_key TEXT")
        }
        if !projectColumns.contains("shotgrid_site") {
            try db.execute(sql: "ALTER TABLE projects ADD COLUMN shotgrid_site TEXT")
        }

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
                proxy_lut TEXT,
                proxy_color_space TEXT,
                narrative_meta TEXT,
                documentary_meta TEXT,
                audio_tracks TEXT NOT NULL DEFAULT '[]',
                sync_result TEXT NOT NULL DEFAULT '{}',
                synced_audio_path TEXT,
                camera_group_id TEXT,
                camera_angle TEXT,
                ai_scores TEXT,
                transcript_id TEXT,
                transcript TEXT,
                transcript_status TEXT DEFAULT 'pending',
                ai_processing_status TEXT NOT NULL DEFAULT 'pending',
                review_status TEXT NOT NULL DEFAULT 'unreviewed',
                annotations TEXT NOT NULL DEFAULT '[]',
                approval_status TEXT NOT NULL DEFAULT 'pending',
                approved_by TEXT,
                approved_at TEXT,
                ingested_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                project_mode TEXT NOT NULL,
                camera_metadata TEXT
            )
        """)

        // Add columns for databases created before each feature landed.
        let clipColumns = Set(try Row.fetchAll(db, sql: "PRAGMA table_info(clips)").compactMap { row in
            row["name"] as String?
        })
        if !clipColumns.contains("transcript") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN transcript TEXT")
        }
        if !clipColumns.contains("transcript_status") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN transcript_status TEXT DEFAULT 'pending'")
        }
        if !clipColumns.contains("camera_metadata") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN camera_metadata TEXT")
        }
        // v1.2 — proxy LUT + multi-cam group
        if !clipColumns.contains("proxy_lut") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN proxy_lut TEXT")
        }
        if !clipColumns.contains("proxy_color_space") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN proxy_color_space TEXT")
        }
        if !clipColumns.contains("camera_group_id") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN camera_group_id TEXT")
        }
        if !clipColumns.contains("camera_angle") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN camera_angle TEXT")
        }
        if !clipColumns.contains("proxy_r2_url") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN proxy_r2_url TEXT")
        }
        if !clipColumns.contains("proxy_r2_uploaded_at") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN proxy_r2_uploaded_at TEXT")
        }
        if !clipColumns.contains("airtable_record_id") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN airtable_record_id TEXT")
        }
        if !clipColumns.contains("shotgrid_entity_id") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN shotgrid_entity_id TEXT")
        }
        if !clipColumns.contains("editorial_updated_at") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN editorial_updated_at TEXT")
        }
        if !clipColumns.contains("custom_proxy_lut_path") {
            try db.execute(sql: "ALTER TABLE clips ADD COLUMN custom_proxy_lut_path TEXT")
        }

        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS watch_folders (
                path TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL,
                mode TEXT NOT NULL,
                upload_throttle_bps INTEGER,
                transcode_profile TEXT,
                created_at TEXT NOT NULL
            )
        """)

        let watchFolderColumns = Set(try Row.fetchAll(db, sql: "PRAGMA table_info(watch_folders)").compactMap { row in
            row["name"] as String?
        })
        if !watchFolderColumns.contains("burn_in_config") {
            try db.execute(sql: "ALTER TABLE watch_folders ADD COLUMN burn_in_config TEXT")
        }
        if !watchFolderColumns.contains("upload_throttle_bps") {
            try db.execute(sql: "ALTER TABLE watch_folders ADD COLUMN upload_throttle_bps INTEGER")
        }
        if !watchFolderColumns.contains("transcode_profile") {
            try db.execute(sql: "ALTER TABLE watch_folders ADD COLUMN transcode_profile TEXT")
        }
        if !watchFolderColumns.contains("offload_destinations") {
            try db.execute(sql: "ALTER TABLE watch_folders ADD COLUMN offload_destinations TEXT DEFAULT '[]'")
        }

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

        // Ingest crash recovery queue
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS ingest_queue (
                id TEXT PRIMARY KEY,
                clip_id TEXT REFERENCES clips(id) ON DELETE CASCADE,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                stage TEXT NOT NULL DEFAULT 'queued',
                -- stage values: queued | copying | checksumming | proxy_pending | proxy_active | sync_pending | ready | failed
                stage_started_at REAL,
                attempts INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
        """)

        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clips_project_id ON clips(project_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_clips_checksum ON clips(checksum)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_assemblies_project_id ON assemblies(project_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_assembly_versions_assembly_id ON assembly_versions(assembly_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ingest_queue_stage ON ingest_queue(stage)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ingest_queue_clip ON ingest_queue(clip_id)")

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

        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS ingest_verification_records (
                id TEXT PRIMARY KEY NOT NULL,
                clip_id TEXT NOT NULL REFERENCES clips(id) ON DELETE CASCADE,
                source_path TEXT NOT NULL,
                destination_path TEXT NOT NULL,
                hash_algorithm TEXT NOT NULL,
                source_hash TEXT NOT NULL,
                destination_hash TEXT NOT NULL,
                bytes_copied INTEGER NOT NULL,
                verified_at TEXT NOT NULL,
                manifest_path TEXT,
                sync_status TEXT NOT NULL DEFAULT 'pending',
                attempts INTEGER NOT NULL DEFAULT 0,
                next_retry_at REAL,
                last_error TEXT
            )
        """)
        let verificationColumns = Set(try Row.fetchAll(db, sql: "PRAGMA table_info(ingest_verification_records)").compactMap { row in
            row["name"] as String?
        })
        if !verificationColumns.contains("attempts") {
            try db.execute(sql: "ALTER TABLE ingest_verification_records ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0")
        }
        if !verificationColumns.contains("next_retry_at") {
            try db.execute(sql: "ALTER TABLE ingest_verification_records ADD COLUMN next_retry_at REAL")
        }
        if !verificationColumns.contains("last_error") {
            try db.execute(sql: "ALTER TABLE ingest_verification_records ADD COLUMN last_error TEXT")
        }
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ingest_verification_clip_id ON ingest_verification_records(clip_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ingest_verification_sync_status ON ingest_verification_records(sync_status)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ingest_verification_next_retry ON ingest_verification_records(next_retry_at)")
    }

    /// Persists a parsed screenplay and returns the new script row id.
    @discardableResult
    public func saveScriptImport(projectId: String, result: ScriptImportResult) async throws -> String {
        let queue = try q()
        let scriptId = UUID().uuidString
        let scenesJSON = try Self.encodeJSON(result.scenes) ?? "[]"
        let sourceName = result.sourceURL.lastPathComponent
        try await queue.write { db in
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
                    sourceName,
                    result.parsedAt
                ]
            )
        }
        return scriptId
    }

    public func replaceClipScriptMappings(scriptId: String, mappings: [ClipScriptMapping]) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM clip_script_mappings WHERE script_id = ?",
                arguments: [scriptId]
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
    }

    private static func decodeClip(from row: Row) throws -> Clip {
        let clip = Clip(
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
        // Note: transcript is persisted but not part of the Clip model yet
        return clip
    }

    private static func decodeWatchFolder(from row: Row) -> WatchFolder? {
        guard let mode = ProjectMode(rawValue: row["mode"]) else {
            return nil
        }
        let burnIn: BurnInConfig?
        if let payload = row["burn_in_config"] as String?, !payload.isEmpty {
            burnIn = try? JSONDecoder().decode(BurnInConfig.self, from: Data(payload.utf8))
        } else {
            burnIn = nil
        }
        let transcodeProfile: ProxyTranscodeProfile?
        if let payload = row["transcode_profile"] as String?, !payload.isEmpty {
            transcodeProfile = try? JSONDecoder().decode(ProxyTranscodeProfile.self, from: Data(payload.utf8))
        } else {
            transcodeProfile = nil
        }
        return WatchFolder(
            path: row["path"],
            projectId: row["project_id"],
            mode: mode,
            burnInConfig: burnIn,
            uploadThrottleBytesPerSecond: row["upload_throttle_bps"],
            transcodeProfile: transcodeProfile,
            offloadDestinations: (try? decodeJSON(row["offload_destinations"], as: [OffloadDestination].self)) ?? []
        )
    }

    private static func encodeJSON<T: Encodable>(_ value: T?) throws -> String? {
        guard let value else {
            return nil
        }

        do {
            let data = try JSONEncoder().encode(value)
            return String(data: data, encoding: .utf8)
        } catch {
            throw GRDBStoreError.encodingFailed(error.localizedDescription)
        }
    }

    private static func decodeJSON<T: Decodable>(_ payload: String?, as type: T.Type) throws -> T? {
        guard let payload, !payload.isEmpty else {
            return nil
        }

        do {
            return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
        } catch {
            throw GRDBStoreError.decodingFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Ingest Queue Management
    
    public struct IngestQueueItem: Codable, Sendable {
        public let id: String
        public let clipId: String
        public let sourcePath: String
        public let destinationPath: String
        public var stage: IngestStage
        public var stageStartedAt: Date?
        public var attempts: Int
        public var lastError: String?
        public let createdAt: Date
        public var updatedAt: Date
        
        public init(
            id: String = UUID().uuidString,
            clipId: String,
            sourcePath: String,
            destinationPath: String,
            stage: IngestStage = .queued
        ) {
            self.id = id
            self.clipId = clipId
            self.sourcePath = sourcePath
            self.destinationPath = destinationPath
            self.stage = stage
            self.stageStartedAt = nil
            self.attempts = 0
            self.lastError = nil
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
    
    public enum IngestStage: String, Codable, Sendable {
        case queued, copying, checksumming, proxyPending, proxyActive, syncPending, ready, failed
    }
    
    public func addToIngestQueue(_ item: IngestQueueItem) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ingest_queue (
                        id, clip_id, source_path, destination_path, stage,
                        stage_started_at, attempts, last_error, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    item.id,
                    item.clipId,
                    item.sourcePath,
                    item.destinationPath,
                    item.stage.rawValue,
                    item.stageStartedAt?.timeIntervalSince1970,
                    item.attempts,
                    item.lastError,
                    item.createdAt.timeIntervalSince1970,
                    item.updatedAt.timeIntervalSince1970
                ]
            )
        }
    }
    
    public func updateIngestQueueStage(id: String, stage: IngestStage, startedAt: Date? = nil, error: String? = nil) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE ingest_queue 
                    SET stage = ?, stage_started_at = ?, attempts = attempts + 1, 
                        last_error = ?, updated_at = ?
                    WHERE id = ?
                """,
                arguments: [
                    stage.rawValue,
                    startedAt?.timeIntervalSince1970,
                    error,
                    Date().timeIntervalSince1970,
                    id
                ]
            )
        }
    }
    
    public func fetchStuckIngestQueue(olderThan cutoffTimestamp: TimeInterval) async throws -> [IngestQueueItem] {
        let queue = try q()
        return try await queue.read { db in
            // Must match IngestStage.rawValue written by updateIngestQueueStage (camelCase)
            let stuckStages = [
                IngestStage.copying.rawValue,
                IngestStage.checksumming.rawValue,
                IngestStage.proxyActive.rawValue
            ]
            let placeholders = stuckStages.map { _ in "?" }.joined(separator: ",")

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM ingest_queue
                    WHERE stage IN (\(placeholders))
                    AND stage_started_at IS NOT NULL
                    AND stage_started_at < ?
                    ORDER BY created_at ASC
                """,
                arguments: StatementArguments(stuckStages + [cutoffTimestamp])
            )

            return rows.compactMap { row in
                guard let stage = IngestStage(rawValue: row["stage"]) else { return nil }
                return IngestQueueItem(
                    id: row["id"],
                    clipId: row["clip_id"],
                    sourcePath: row["source_path"],
                    destinationPath: row["destination_path"],
                    stage: stage
                )
            }
        }
    }
    
    public func fetchIngestQueue(whereStageIn stages: [IngestStage]) async throws -> [IngestQueueItem] {
        let queue = try q()
        return try await queue.read { db in
            let placeholders = stages.map { _ in "?" }.joined(separator: ",")
            let stageStrings = stages.map { $0.rawValue }
            
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM ingest_queue 
                    WHERE stage IN (\(placeholders))
                    ORDER BY created_at ASC
                """,
                arguments: StatementArguments(stageStrings)
            )
            
            return rows.compactMap { row in
                guard let stage = IngestStage(rawValue: row["stage"]) else { return nil }
                return IngestQueueItem(
                    id: row["id"],
                    clipId: row["clip_id"],
                    sourcePath: row["source_path"],
                    destinationPath: row["destination_path"],
                    stage: stage
                )
            }
        }
    }

    public struct IngestVerificationRecord: Codable, Sendable {
        public var id: String
        public var clipId: String
        public var sourcePath: String
        public var destinationPath: String
        public var hashAlgorithm: String
        public var sourceHash: String
        public var destinationHash: String
        public var bytesCopied: Int64
        public var verifiedAt: String
        public var manifestPath: String?
        public var syncStatus: String
        public var attempts: Int
        public var nextRetryAt: Double?
        public var lastError: String?

        public init(
            id: String = UUID().uuidString,
            clipId: String,
            sourcePath: String,
            destinationPath: String,
            hashAlgorithm: String,
            sourceHash: String,
            destinationHash: String,
            bytesCopied: Int64,
            verifiedAt: String,
            manifestPath: String?,
            syncStatus: String = "pending",
            attempts: Int = 0,
            nextRetryAt: Double? = nil,
            lastError: String? = nil
        ) {
            self.id = id
            self.clipId = clipId
            self.sourcePath = sourcePath
            self.destinationPath = destinationPath
            self.hashAlgorithm = hashAlgorithm
            self.sourceHash = sourceHash
            self.destinationHash = destinationHash
            self.bytesCopied = bytesCopied
            self.verifiedAt = verifiedAt
            self.manifestPath = manifestPath
            self.syncStatus = syncStatus
            self.attempts = attempts
            self.nextRetryAt = nextRetryAt
            self.lastError = lastError
        }
    }

    public func saveIngestVerificationRecord(_ record: IngestVerificationRecord) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ingest_verification_records (
                        id, clip_id, source_path, destination_path, hash_algorithm,
                        source_hash, destination_hash, bytes_copied, verified_at, manifest_path,
                        sync_status, attempts, next_retry_at, last_error
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        clip_id = excluded.clip_id,
                        source_path = excluded.source_path,
                        destination_path = excluded.destination_path,
                        hash_algorithm = excluded.hash_algorithm,
                        source_hash = excluded.source_hash,
                        destination_hash = excluded.destination_hash,
                        bytes_copied = excluded.bytes_copied,
                        verified_at = excluded.verified_at,
                        manifest_path = excluded.manifest_path,
                        sync_status = excluded.sync_status,
                        attempts = excluded.attempts,
                        next_retry_at = excluded.next_retry_at,
                        last_error = excluded.last_error
                """,
                arguments: [
                    record.id,
                    record.clipId,
                    record.sourcePath,
                    record.destinationPath,
                    record.hashAlgorithm,
                    record.sourceHash,
                    record.destinationHash,
                    record.bytesCopied,
                    record.verifiedAt,
                    record.manifestPath,
                    record.syncStatus,
                    record.attempts,
                    record.nextRetryAt,
                    record.lastError
                ]
            )
        }
    }

    public func fetchPendingVerificationRecords(limit: Int = 100) async throws -> [IngestVerificationRecord] {
        let queue = try q()
        let now = Date().timeIntervalSince1970
        return try await queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM ingest_verification_records
                    WHERE sync_status IN ('pending', 'retry')
                      AND (next_retry_at IS NULL OR next_retry_at <= ?)
                    ORDER BY verified_at ASC
                    LIMIT ?
                """,
                arguments: [now, max(1, limit)]
            )
            return rows.map { row in
                IngestVerificationRecord(
                    id: row["id"],
                    clipId: row["clip_id"],
                    sourcePath: row["source_path"],
                    destinationPath: row["destination_path"],
                    hashAlgorithm: row["hash_algorithm"],
                    sourceHash: row["source_hash"],
                    destinationHash: row["destination_hash"],
                    bytesCopied: row["bytes_copied"],
                    verifiedAt: row["verified_at"],
                    manifestPath: row["manifest_path"],
                    syncStatus: row["sync_status"],
                    attempts: row["attempts"],
                    nextRetryAt: row["next_retry_at"],
                    lastError: row["last_error"]
                )
            }
        }
    }

    public func markVerificationRecordSynced(id: String) async throws {
        let queue = try q()
        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE ingest_verification_records
                    SET sync_status = 'synced',
                        next_retry_at = NULL,
                        last_error = NULL
                    WHERE id = ?
                """,
                arguments: [id]
            )
        }
    }

    public func markVerificationRecordRetry(id: String, attempts: Int, error: String) async throws {
        let queue = try q()
        let backoffSeconds = pow(2.0, Double(max(0, attempts - 1))) * 5.0
        let nextRetry = Date().timeIntervalSince1970 + min(backoffSeconds, 60 * 60)
        try await queue.write { db in
            try db.execute(
                sql: """
                    UPDATE ingest_verification_records
                    SET sync_status = 'retry',
                        attempts = ?,
                        next_retry_at = ?,
                        last_error = ?
                    WHERE id = ?
                """,
                arguments: [attempts, nextRetry, error, id]
            )
        }
    }
}
