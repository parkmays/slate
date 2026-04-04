// SLATE — ProjectStore
// Owned by: Claude Code
//
// Lightweight desktop-side project state. For C2 this mirrors the projects
// discovered in the shared GRDB database and supports local project/watch
// folder creation flows.

import Foundation
import IngestDaemon
import Supabase
import SwiftUI
import SLATESharedTypes

public struct ProjectImportResult: Sendable {
    public let importedClips: [Clip]
    public let failedItems: [IngestError]

    public init(importedClips: [Clip], failedItems: [IngestError]) {
        self.importedClips = importedClips
        self.failedItems = failedItems
    }
}

public enum ProjectImportError: LocalizedError {
    case noSupportedMedia

    public var errorDescription: String? {
        switch self {
        case .noSupportedMedia:
            return "Drop camera media files or folders containing supported media to import."
        }
    }
}

@MainActor
public final class ProjectStore: ObservableObject {
    @Published public var projects: [Project] = []
    @Published public var activeProject: Project?
    @Published public var loading = false
    @Published public var error: Error?

    private let supabase: SupabaseClient?
    private let userId: String
    private var watchFoldersByProject: [String: [WatchFolder]] = [:]
    private var manualImportReport = IngestProgressReport()

    nonisolated private static let supportedMediaExtensions: Set<String> = [
        "ari", "arx", "braw", "mov", "mp4", "mxf", "r3d"
    ]

    public init(supabase: SupabaseClient? = nil, userId: String = "local-user") {
        self.supabase = supabase
        self.userId = userId
    }

    public func setProjects(_ projects: [Project]) {
        self.projects = projects.sorted { $0.updatedAt > $1.updatedAt }

        if let activeProject, self.projects.contains(where: { $0.id == activeProject.id }) {
            return
        }

        activeProject = self.projects.first
    }

    public func createProject(name: String, mode: ProjectMode) async throws -> Project {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let project = Project(
            id: UUID().uuidString,
            name: name,
            mode: mode,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let dbPath = GRDBClipStore.defaultDBPath()
        try await GRDBStore.shared.setup(at: dbPath)
        try await GRDBStore.shared.saveProject(project)

        projects.insert(project, at: 0)
        activeProject = project
        return project
    }

    public func setActiveProject(_ project: Project) {
        activeProject = project
    }

    public func addWatchFolder(path: String, to project: Project) async throws -> WatchFolder {
        let watchFolder = WatchFolder(path: path, projectId: project.id, mode: project.mode)
        watchFoldersByProject[project.id, default: []].append(watchFolder)

        let dbPath = GRDBClipStore.defaultDBPath()
        try await GRDBStore.shared.setup(at: dbPath)
        try await GRDBStore.shared.saveWatchFolder(watchFolder)

        NotificationCenter.default.post(
            name: .watchFoldersUpdated,
            object: nil,
            userInfo: ["projectId": project.id]
        )

        return watchFolder
    }

    public func getWatchFolders(for project: Project) async throws -> [WatchFolder] {
        if let cached = watchFoldersByProject[project.id] {
            return cached
        }

        let dbPath = GRDBClipStore.defaultDBPath()
        try await GRDBStore.shared.setup(at: dbPath)
        let allFolders = try await GRDBStore.shared.allWatchFolders()
        let projectFolders = allFolders.filter { $0.projectId == project.id }
        watchFoldersByProject[project.id] = projectFolders
        return projectFolders
    }

    public func importMedia(from urls: [URL], to project: Project) async throws -> ProjectImportResult {
        let mediaFiles = await Task.detached(priority: .userInitiated) {
            Self.importableMediaURLs(from: urls)
        }.value

        guard !mediaFiles.isEmpty else {
            throw ProjectImportError.noSupportedMedia
        }

        let dbPath = GRDBClipStore.defaultDBPath()
        try await GRDBStore.shared.setup(at: dbPath)

        beginManualImport(totalCount: mediaFiles.count)

        var importedClips: [Clip] = []
        var failedItems: [IngestError] = []

        for (index, mediaURL) in mediaFiles.enumerated() {
            let remainingQueued = max(mediaFiles.count - index - 1, 0)
            let watchConfig = WatchFolder(
                path: mediaURL.deletingLastPathComponent().path,
                projectId: project.id,
                mode: project.mode
            )

            let pipeline = IngestPipeline(
                watchConfig: watchConfig,
                store: .shared
            ) { [weak self] item in
                Task { @MainActor in
                    self?.applyManualImportProgress(item, queued: remainingQueued)
                }
            }

            do {
                let clip = try await pipeline.ingest(sourceURL: mediaURL)
                importedClips.append(clip)
                applyManualImportProgress(
                    .init(
                        filename: mediaURL.lastPathComponent,
                        progress: 1.0,
                        stage: .complete
                    ),
                    queued: remainingQueued
                )
            } catch {
                let ingestError = IngestError(
                    filename: mediaURL.lastPathComponent,
                    message: error.localizedDescription
                )
                failedItems.append(ingestError)
                recordManualImportError(ingestError, queued: remainingQueued)
            }
        }

        finishManualImport()
        return ProjectImportResult(importedClips: importedClips, failedItems: failedItems)
    }

    private func beginManualImport(totalCount: Int) {
        manualImportReport = IngestProgressReport(active: [], queued: totalCount, errors: [])
        publishManualImportProgress()
    }

    private func applyManualImportProgress(_ item: IngestProgressItem, queued: Int) {
        manualImportReport.queued = queued
        manualImportReport.active.removeAll { $0.filename == item.filename }

        if item.stage == .error {
            if let message = item.error {
                appendManualImportError(
                    .init(filename: item.filename, message: message)
                )
            }
        } else if item.stage != .complete {
            manualImportReport.active.append(item)
        }

        publishManualImportProgress()
    }

    private func recordManualImportError(_ error: IngestError, queued: Int) {
        manualImportReport.queued = queued
        manualImportReport.active.removeAll { $0.filename == error.filename }
        appendManualImportError(error)
        publishManualImportProgress()
    }

    private func finishManualImport() {
        manualImportReport.active = []
        manualImportReport.queued = 0
        publishManualImportProgress()
    }

    private func appendManualImportError(_ error: IngestError) {
        let isDuplicate = manualImportReport.errors.contains {
            $0.filename == error.filename && $0.message == error.message
        }
        if !isDuplicate {
            manualImportReport.errors.append(error)
        }
    }

    private func publishManualImportProgress() {
        NotificationCenter.default.post(
            name: .ingestProgressUpdated,
            object: manualImportReport
        )
    }

    nonisolated private static func importableMediaURLs(from urls: [URL]) -> [URL] {
        var uniquePaths = Set<String>()
        var mediaFiles: [URL] = []
        let fileManager = FileManager.default

        func appendIfSupported(_ candidateURL: URL) {
            let standardizedURL = candidateURL.standardizedFileURL
            guard uniquePaths.insert(standardizedURL.path).inserted else {
                return
            }

            guard isSupportedMediaFile(standardizedURL) else {
                return
            }

            mediaFiles.append(standardizedURL)
        }

        for url in urls {
            let standardizedURL = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                guard let enumerator = fileManager.enumerator(
                    at: standardizedURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                for case let nestedURL as URL in enumerator {
                    appendIfSupported(nestedURL)
                }
            } else {
                appendIfSupported(standardizedURL)
            }
        }

        return mediaFiles.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    nonisolated private static func isSupportedMediaFile(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        guard supportedMediaExtensions.contains(pathExtension) else {
            return false
        }

        let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return resourceValues?.isRegularFile ?? true
    }
}
