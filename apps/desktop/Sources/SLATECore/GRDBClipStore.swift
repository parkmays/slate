// SLATE — GRDBClipStore
// Owned by: Claude Code
//
// Desktop-side read-mostly store for the canonical SQLite database shared with
// the ingest daemon.

import Combine
import Foundation
import GRDB
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
                        SELECT id, name, mode, created_at, updated_at
                        FROM projects
                        ORDER BY updated_at DESC, created_at DESC
                    """
                )
            }
            projects = rows.compactMap(Self.decodeProject(from:))
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
        }
    }

    private static func makeStatistics(from clips: [Clip]) -> ProjectStatistics {
        let totalClips = clips.count
        guard totalClips > 0 else {
            return .empty
        }

        let reviewedCount = clips.filter { $0.reviewStatus != .unreviewed }.count
        let readyProxies = clips.filter { $0.proxyStatus == .ready }.count

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
            updatedAt: row["updated_at"]
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
            narrativeMeta: try decodeJSON(row["narrative_meta"], as: NarrativeMeta.self),
            documentaryMeta: try decodeJSON(row["documentary_meta"], as: DocumentaryMeta.self),
            audioTracks: try decodeJSON(row["audio_tracks"], as: [AudioTrack].self) ?? [],
            syncResult: try decodeJSON(row["sync_result"], as: SyncResult.self) ?? .unsynced,
            syncedAudioPath: row["synced_audio_path"],
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
            projectMode: ProjectMode(rawValue: row["project_mode"]) ?? .narrative
        )
    }

    private static func decodeJSON<T: Decodable>(_ payload: String?, as type: T.Type) throws -> T? {
        guard let payload, !payload.isEmpty else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: Data(payload.utf8))
    }
}
