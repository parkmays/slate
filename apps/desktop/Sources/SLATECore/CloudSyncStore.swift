import ExportWriters
import CryptoKit
import Foundation
import GRDB
import SwiftUI
import UniformTypeIdentifiers
import SLATESharedTypes

public enum CloudSyncProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case googleDrive = "google_drive"
    case dropbox
    case amazonS3 = "amazon_s3"
    case frameIO = "frame_io"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .googleDrive:
            return "Google Drive"
        case .dropbox:
            return "Dropbox"
        case .amazonS3:
            return "Amazon S3"
        case .frameIO:
            return "Frame.io"
        }
    }

    public var tokenEnvironmentVariable: String {
        switch self {
        case .googleDrive:
            return "SLATE_GOOGLE_DRIVE_ACCESS_TOKEN"
        case .dropbox:
            return "SLATE_DROPBOX_ACCESS_TOKEN"
        case .amazonS3:
            return "SLATE_S3_ACCESS_KEY_ID"
        case .frameIO:
            return "SLATE_FRAMEIO_ACCESS_TOKEN"
        }
    }

    public var iconName: String {
        switch self {
        case .googleDrive:
            return "externaldrive.badge.icloud"
        case .dropbox:
            return "shippingbox"
        case .amazonS3:
            return "externaldrive.connected.to.line.below"
        case .frameIO:
            return "play.rectangle.on.rectangle"
        }
    }
}

public enum CloudSyncAssetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case footage
    case edit
    case comments

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .footage:
            return "Footage"
        case .edit:
            return "Edits"
        case .comments:
            return "Comments"
        }
    }
}

public enum CloudSyncRecordStatus: String, Codable, CaseIterable, Sendable {
    case synced
    case failed
}

public struct CloudSyncDestinationConfiguration: Codable, Sendable, Equatable {
    public var remotePath: String?
    public var remoteFolderId: String?
    public var accountId: String?

    public init(
        remotePath: String? = nil,
        remoteFolderId: String? = nil,
        accountId: String? = nil
    ) {
        self.remotePath = remotePath
        self.remoteFolderId = remoteFolderId
        self.accountId = accountId
    }

    public func validated(for provider: CloudSyncProvider) throws -> CloudSyncDestinationConfiguration {
        func trimmed(_ value: String?) -> String? {
            guard let value else { return nil }
            let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }

        let normalized = CloudSyncDestinationConfiguration(
            remotePath: trimmed(remotePath),
            remoteFolderId: trimmed(remoteFolderId),
            accountId: trimmed(accountId)
        )

        switch provider {
        case .googleDrive:
            guard normalized.remoteFolderId != nil else {
                throw CloudSyncStoreError.invalidDestination("Google Drive destinations need a folder ID.")
            }
        case .dropbox:
            guard normalized.remotePath != nil else {
                throw CloudSyncStoreError.invalidDestination("Dropbox destinations need a folder path like /Apps/SLATE.")
            }
        case .amazonS3:
            guard normalized.remotePath != nil else {
                throw CloudSyncStoreError.invalidDestination("S3 destinations need a prefix path (for example projects/slate).")
            }
        case .frameIO:
            guard normalized.accountId != nil, normalized.remoteFolderId != nil else {
                throw CloudSyncStoreError.invalidDestination("Frame.io destinations need both an account ID and a folder ID.")
            }
        }

        return normalized
    }
}

public struct CloudSyncDestination: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var provider: CloudSyncProvider
    public var name: String
    public var configuration: CloudSyncDestinationConfiguration
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        provider: CloudSyncProvider,
        name: String,
        configuration: CloudSyncDestinationConfiguration,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.projectId = projectId
        self.provider = provider
        self.name = name
        self.configuration = configuration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CloudSyncRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var projectId: String
    public var destinationId: String
    public var provider: CloudSyncProvider
    public var assetKind: CloudSyncAssetKind
    public var assetLabel: String
    public var localPath: String
    public var remoteIdentifier: String?
    public var remotePath: String?
    public var remoteURL: String?
    public var byteCount: Int64
    public var status: CloudSyncRecordStatus
    public var errorMessage: String?
    public var syncedAt: String

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        destinationId: String,
        provider: CloudSyncProvider,
        assetKind: CloudSyncAssetKind,
        assetLabel: String,
        localPath: String,
        remoteIdentifier: String? = nil,
        remotePath: String? = nil,
        remoteURL: String? = nil,
        byteCount: Int64,
        status: CloudSyncRecordStatus,
        errorMessage: String? = nil,
        syncedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.projectId = projectId
        self.destinationId = destinationId
        self.provider = provider
        self.assetKind = assetKind
        self.assetLabel = assetLabel
        self.localPath = localPath
        self.remoteIdentifier = remoteIdentifier
        self.remotePath = remotePath
        self.remoteURL = remoteURL
        self.byteCount = byteCount
        self.status = status
        self.errorMessage = errorMessage
        self.syncedAt = syncedAt
    }
}

public struct CloudSyncOptions: Sendable {
    public var includeFootage: Bool
    public var includeEdit: Bool
    public var includeComments: Bool

    public init(
        includeFootage: Bool = true,
        includeEdit: Bool = true,
        includeComments: Bool = true
    ) {
        self.includeFootage = includeFootage
        self.includeEdit = includeEdit
        self.includeComments = includeComments
    }
}

public struct CloudSyncFailure: Sendable, Identifiable {
    public let id = UUID()
    public let assetLabel: String
    public let message: String
}

public struct CloudSyncSummary: Sendable {
    public let uploadedCount: Int
    public let failedCount: Int
    public let failures: [CloudSyncFailure]

    public init(uploadedCount: Int, failedCount: Int, failures: [CloudSyncFailure]) {
        self.uploadedCount = uploadedCount
        self.failedCount = failedCount
        self.failures = failures
    }
}

public struct CloudSyncPullSummary: Sendable {
    public let discoveredCount: Int
    public let downloadedCount: Int
    public let importedFootageCount: Int
    public let mergedClipCount: Int
    public let updatedAssemblyCount: Int
    public let failures: [CloudSyncFailure]

    public init(
        discoveredCount: Int,
        downloadedCount: Int,
        importedFootageCount: Int,
        mergedClipCount: Int,
        updatedAssemblyCount: Int,
        failures: [CloudSyncFailure]
    ) {
        self.discoveredCount = discoveredCount
        self.downloadedCount = downloadedCount
        self.importedFootageCount = importedFootageCount
        self.mergedClipCount = mergedClipCount
        self.updatedAssemblyCount = updatedAssemblyCount
        self.failures = failures
    }

    public var failedCount: Int {
        failures.count
    }
}

private struct CloudSyncCommentsManifest: Codable {
    struct ClipEntry: Codable {
        let clipId: String
        let checksum: String?
        let fileName: String
        let sourcePath: String
        let reviewStatus: String
        let approvalStatus: String
        let approvedBy: String?
        let approvedAt: String?
        let updatedAt: String
        let annotations: [Annotation]
    }

    struct AssemblyEntry: Codable {
        let id: String
        let name: String
        let version: Int
        let clipCount: Int
        let createdAt: String
    }

    let projectId: String
    let projectName: String
    let generatedAt: String
    let clips: [ClipEntry]
    let assemblies: [AssemblyEntry]
}

private struct CloudSyncAssemblyArchivePayload: Decodable {
    struct ClipSnapshot: Decodable {
        let clipId: String
        let checksum: String?
        let filename: String
        let sourcePath: String
        let proxyPath: String?
        let reviewStatus: String
        let sceneLabel: String
        let role: String
        let inPoint: Double
        let outPoint: Double
        let annotations: [Annotation]
    }

    let assembly: Assembly
    let exportedAt: String
    let clips: [ClipSnapshot]
}

private enum CloudRemoteLocator: Sendable {
    case googleFile(String)
    case dropboxPath(String)
    case frameIOFile(accountId: String, fileId: String)
    case directURL(URL)
}

private struct CloudRemoteAsset: Sendable {
    let name: String
    let locator: CloudRemoteLocator
    let remotePath: String?
    let remoteURL: String?
    let byteCount: Int64
    let modifiedAt: String?
}

private struct RemoteFootageImportResult: Sendable {
    let downloadedCount: Int
    let importedFootageCount: Int
    let failures: [CloudSyncFailure]
}

public enum CloudSyncStoreError: LocalizedError {
    case invalidDestination(String)
    case providerTokenMissing(CloudSyncProvider)
    case databaseUnavailable
    case noSyncableAssets
    case noRemoteAssets
    case assemblyUnavailable
    case uploadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDestination(let message):
            return message
        case .providerTokenMissing(let provider):
            return "Set \(provider.tokenEnvironmentVariable) before syncing to \(provider.displayName)."
        case .databaseUnavailable:
            return "The cloud sync database is not available yet."
        case .noSyncableAssets:
            return "There is nothing to sync for the selected options."
        case .noRemoteAssets:
            return "No remote assets were found for this destination yet."
        case .assemblyUnavailable:
            return "No assembly exists yet for this project, so there are no edits to sync."
        case .uploadFailed(let message):
            return message
        }
    }
}

private struct CloudSyncAssetDescriptor: Sendable {
    let kind: CloudSyncAssetKind
    let label: String
    let localIdentifier: String
    let fileURL: URL
    let remoteName: String
}

private struct ProviderUploadResult: Sendable {
    let remoteIdentifier: String?
    let remotePath: String?
    let remoteURL: String?
    let byteCount: Int64
}

@MainActor
public final class CloudSyncStore: ObservableObject {
    @Published public private(set) var destinations: [CloudSyncDestination] = []
    @Published public private(set) var records: [CloudSyncRecord] = []
    @Published public private(set) var loading = false
    @Published public private(set) var isSyncing = false
    @Published public var errorMessage: String?

    private let dbPath: String
    private var dbQueue: DatabaseQueue?
    private var selectedProjectId: String?

    public init(dbPath: String = GRDBClipStore.defaultDBPath()) {
        self.dbPath = dbPath
    }

    public func load(project: Project) async {
        loading = true
        errorMessage = nil

        do {
            try openDatabaseIfNeeded()
            selectedProjectId = project.id
            destinations = try loadDestinations(projectId: project.id)
            records = try loadRecords(projectId: project.id)
        } catch {
            errorMessage = error.localizedDescription
            destinations = []
            records = []
        }

        loading = false
    }

    public func saveDestination(
        name: String,
        provider: CloudSyncProvider,
        configuration: CloudSyncDestinationConfiguration,
        project: Project
    ) async throws {
        try openDatabaseIfNeeded()

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CloudSyncStoreError.invalidDestination("Give the destination a name so the team can tell where it points.")
        }

        let validatedConfiguration = try configuration.validated(for: provider)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let destination = CloudSyncDestination(
            projectId: project.id,
            provider: provider,
            name: trimmedName,
            configuration: validatedConfiguration,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try saveDestination(destination)
        destinations = try loadDestinations(projectId: project.id)
    }

    public func deleteDestination(_ destination: CloudSyncDestination) async throws {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        try await dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM cloud_sync_records WHERE destination_id = ?",
                arguments: [destination.id]
            )
            try db.execute(
                sql: "DELETE FROM cloud_sync_destinations WHERE id = ?",
                arguments: [destination.id]
            )
        }

        if let selectedProjectId {
            destinations = try loadDestinations(projectId: selectedProjectId)
            records = try loadRecords(projectId: selectedProjectId)
        }
    }

    public func sync(
        project: Project,
        clips: [Clip],
        destination: CloudSyncDestination,
        options: CloudSyncOptions,
        authManager: CloudAuthManager? = nil
    ) async throws -> CloudSyncSummary {
        try openDatabaseIfNeeded()

        let client = try await makeClient(for: destination, authManager: authManager)
        let assetPlan = try buildAssetPlan(project: project, clips: clips, options: options)
        guard !assetPlan.isEmpty else {
            throw CloudSyncStoreError.noSyncableAssets
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        var uploadedCount = 0
        var failures: [CloudSyncFailure] = []

        for asset in assetPlan {
            do {
                let result = try await client.upload(
                    fileURL: asset.fileURL,
                    remoteName: asset.remoteName,
                    destination: destination
                )
                let record = CloudSyncRecord(
                    projectId: project.id,
                    destinationId: destination.id,
                    provider: destination.provider,
                    assetKind: asset.kind,
                    assetLabel: asset.label,
                    localPath: asset.fileURL.path,
                    remoteIdentifier: result.remoteIdentifier,
                    remotePath: result.remotePath,
                    remoteURL: result.remoteURL,
                    byteCount: result.byteCount,
                    status: .synced
                )
                try saveRecord(record)
                uploadedCount += 1
            } catch {
                let record = CloudSyncRecord(
                    projectId: project.id,
                    destinationId: destination.id,
                    provider: destination.provider,
                    assetKind: asset.kind,
                    assetLabel: asset.label,
                    localPath: asset.fileURL.path,
                    byteCount: (try? fileSize(at: asset.fileURL)) ?? 0,
                    status: .failed,
                    errorMessage: error.localizedDescription
                )
                try saveRecord(record)
                failures.append(.init(assetLabel: asset.label, message: error.localizedDescription))
            }
        }

        records = try loadRecords(projectId: project.id)
        return CloudSyncSummary(
            uploadedCount: uploadedCount,
            failedCount: failures.count,
            failures: failures
        )
    }

    public func pull(
        project: Project,
        clips: [Clip],
        destination: CloudSyncDestination,
        options: CloudSyncOptions,
        projectStore: ProjectStore,
        authManager: CloudAuthManager? = nil
    ) async throws -> CloudSyncPullSummary {
        try openDatabaseIfNeeded()

        let client = try await makeClient(for: destination, authManager: authManager)
        let remoteAssets = try await client.listAssets(destination: destination)
        let filteredAssets = remoteAssets.filter { asset in
            switch remoteAssetKind(for: asset.name, projectName: project.name) {
            case .footage:
                return options.includeFootage
            case .edit:
                return options.includeEdit
            case .comments:
                return options.includeComments
            case nil:
                return false
            }
        }

        guard !filteredAssets.isEmpty else {
            throw CloudSyncStoreError.noRemoteAssets
        }

        isSyncing = true
        errorMessage = nil
        defer { isSyncing = false }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-cloud-sync", isDirectory: true)
            .appendingPathComponent(project.id, isDirectory: true)
            .appendingPathComponent("pull", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        var downloadedCount = 0
        var importedFootageCount = 0
        var mergedClipCount = 0
        var updatedAssemblyCount = 0
        var failures: [CloudSyncFailure] = []
        var latestClips = clips

        let footageAssets = filteredAssets
            .filter { remoteAssetKind(for: $0.name, projectName: project.name) == .footage }
            .sorted(by: remoteAssetSortPredicate)
        let commentsAsset = filteredAssets
            .filter { remoteAssetKind(for: $0.name, projectName: project.name) == .comments }
            .sorted(by: remoteAssetSortPredicate)
            .first
        let editAsset = filteredAssets
            .filter { remoteAssetKind(for: $0.name, projectName: project.name) == .edit }
            .sorted(by: remoteAssetSortPredicate)
            .first

        do {
            let importResult = try await importRemoteFootage(
                assets: footageAssets,
                project: project,
                existingClips: latestClips,
                destination: destination,
                client: client,
                projectStore: projectStore,
                workingDirectory: workingDirectory
            )
            downloadedCount += importResult.downloadedCount
            importedFootageCount += importResult.importedFootageCount
            failures.append(contentsOf: importResult.failures)
            latestClips = try loadProjectClips(projectId: project.id)
        } catch {
            failures.append(.init(assetLabel: "Footage Pull", message: error.localizedDescription))
        }

        if let commentsAsset {
            do {
                let localURL = try await downloadRemoteAsset(
                    commentsAsset,
                    client: client,
                    workingDirectory: workingDirectory,
                    restoredFileName: commentsAsset.name
                )
                let mergedCount = try applyCommentsManifest(at: localURL, projectId: project.id)
                mergedClipCount += mergedCount
                downloadedCount += 1
                latestClips = try loadProjectClips(projectId: project.id)
                try saveRecord(
                    CloudSyncRecord(
                        projectId: project.id,
                        destinationId: destination.id,
                        provider: destination.provider,
                        assetKind: .comments,
                        assetLabel: "Pulled \(commentsAsset.name)",
                        localPath: localURL.path,
                        remoteIdentifier: commentsAsset.remotePath ?? commentsAsset.name,
                        remotePath: commentsAsset.remotePath,
                        remoteURL: commentsAsset.remoteURL,
                        byteCount: commentsAsset.byteCount,
                        status: .synced
                    )
                )
            } catch {
                let failure = CloudSyncFailure(assetLabel: commentsAsset.name, message: error.localizedDescription)
                failures.append(failure)
                try saveFailedPullRecord(
                    for: commentsAsset,
                    destination: destination,
                    projectId: project.id,
                    assetKind: .comments,
                    message: error.localizedDescription
                )
            }
        }

        if let editAsset {
            do {
                let localURL = try await downloadRemoteAsset(
                    editAsset,
                    client: client,
                    workingDirectory: workingDirectory,
                    restoredFileName: editAsset.name
                )
                let updatedCount = try importAssemblyArchive(
                    at: localURL,
                    projectId: project.id,
                    clips: latestClips
                )
                updatedAssemblyCount += updatedCount
                downloadedCount += 1
                try saveRecord(
                    CloudSyncRecord(
                        projectId: project.id,
                        destinationId: destination.id,
                        provider: destination.provider,
                        assetKind: .edit,
                        assetLabel: "Pulled \(editAsset.name)",
                        localPath: localURL.path,
                        remoteIdentifier: editAsset.remotePath ?? editAsset.name,
                        remotePath: editAsset.remotePath,
                        remoteURL: editAsset.remoteURL,
                        byteCount: editAsset.byteCount,
                        status: .synced
                    )
                )
            } catch {
                let failure = CloudSyncFailure(assetLabel: editAsset.name, message: error.localizedDescription)
                failures.append(failure)
                try saveFailedPullRecord(
                    for: editAsset,
                    destination: destination,
                    projectId: project.id,
                    assetKind: .edit,
                    message: error.localizedDescription
                )
            }
        }

        records = try loadRecords(projectId: project.id)
        return CloudSyncPullSummary(
            discoveredCount: filteredAssets.count,
            downloadedCount: downloadedCount,
            importedFootageCount: importedFootageCount,
            mergedClipCount: mergedClipCount,
            updatedAssemblyCount: updatedAssemblyCount,
            failures: failures
        )
    }

    private func buildAssetPlan(
        project: Project,
        clips: [Clip],
        options: CloudSyncOptions
    ) throws -> [CloudSyncAssetDescriptor] {
        var plan: [CloudSyncAssetDescriptor] = []
        let sanitizedProjectName = sanitizedName(project.name)

        if options.includeFootage {
            for clip in clips {
                let sourceURL = URL(fileURLWithPath: clip.sourcePath)
                guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                    continue
                }

                let clipName = sourceURL.lastPathComponent
                plan.append(
                    CloudSyncAssetDescriptor(
                        kind: .footage,
                        label: clipName,
                        localIdentifier: clip.id,
                        fileURL: sourceURL,
                        remoteName: "\(sanitizedProjectName)-footage-\(clipName)"
                    )
                )
            }
        }

        if options.includeEdit {
            if let assemblyDescriptor = try makeAssemblyDescriptor(project: project, clips: clips) {
                plan.append(assemblyDescriptor)
            }
        }

        if options.includeComments {
            plan.append(try makeCommentsDescriptor(project: project, clips: clips))
        }

        return plan
    }

    private func makeAssemblyDescriptor(
        project: Project,
        clips: [Clip]
    ) throws -> CloudSyncAssetDescriptor? {
        guard let assembly = try loadLatestAssembly(projectId: project.id) else {
            return nil
        }

        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-cloud-sync", isDirectory: true)
            .appendingPathComponent(project.id, isDirectory: true)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let artifact = try ExportWriterFactory.writer(for: .assemblyArchive).export(
            context: ExportContext(
                assembly: assembly,
                clipsById: Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) }),
                projectName: project.name
            ),
            to: exportDirectory
        )

        let artifactURL = URL(fileURLWithPath: artifact.filePath)
        let sanitizedProjectName = sanitizedName(project.name)
        return CloudSyncAssetDescriptor(
            kind: .edit,
            label: artifactURL.lastPathComponent,
            localIdentifier: assembly.id,
            fileURL: artifactURL,
            remoteName: "\(sanitizedProjectName)-edit-\(artifactURL.lastPathComponent)"
        )
    }

    private func makeCommentsDescriptor(
        project: Project,
        clips: [Clip]
    ) throws -> CloudSyncAssetDescriptor {
        let assemblies = try loadAssemblies(projectId: project.id)
        let manifest = CloudSyncCommentsManifest(
            projectId: project.id,
            projectName: project.name,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            clips: clips.map { clip in
                CloudSyncCommentsManifest.ClipEntry(
                    clipId: clip.id,
                    checksum: clip.checksum,
                    fileName: URL(fileURLWithPath: clip.sourcePath).lastPathComponent,
                    sourcePath: clip.sourcePath,
                    reviewStatus: clip.reviewStatus.rawValue,
                    approvalStatus: clip.approvalStatus.rawValue,
                    approvedBy: clip.approvedBy,
                    approvedAt: clip.approvedAt,
                    updatedAt: clip.updatedAt,
                    annotations: clip.annotations
                )
            },
            assemblies: assemblies.map { assembly in
                CloudSyncCommentsManifest.AssemblyEntry(
                    id: assembly.id,
                    name: assembly.name,
                    version: assembly.version,
                    clipCount: assembly.clips.count,
                    createdAt: assembly.createdAt
                )
            }
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-cloud-sync", isDirectory: true)
            .appendingPathComponent(project.id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(sanitizedName(project.name))-comments.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: fileURL, options: .atomic)

        return CloudSyncAssetDescriptor(
            kind: .comments,
            label: fileURL.lastPathComponent,
            localIdentifier: project.id,
            fileURL: fileURL,
            remoteName: "\(sanitizedName(project.name))-comments.json"
        )
    }

    private func makeClient(
        for destination: CloudSyncDestination,
        authManager: CloudAuthManager?
    ) async throws -> any CloudStorageProviderClient {
        if destination.provider == .amazonS3 {
            let accessKeyId = ProcessInfo.processInfo.environment["SLATE_S3_ACCESS_KEY_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let secretAccessKey = ProcessInfo.processInfo.environment["SLATE_S3_SECRET_ACCESS_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bucket = ProcessInfo.processInfo.environment["SLATE_S3_BUCKET"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let endpoint = ProcessInfo.processInfo.environment["SLATE_S3_ENDPOINT"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let region = ProcessInfo.processInfo.environment["SLATE_S3_REGION"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "us-east-1"
            guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty, !bucket.isEmpty, !endpoint.isEmpty else {
                throw CloudSyncStoreError.invalidDestination(
                    "Set SLATE_S3_ACCESS_KEY_ID, SLATE_S3_SECRET_ACCESS_KEY, SLATE_S3_BUCKET, and SLATE_S3_ENDPOINT."
                )
            }
            return S3CompatibleCloudClient(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                bucket: bucket,
                endpoint: endpoint,
                region: region
            )
        }

        let token: String
        if let authManager {
            do {
                token = try await authManager.validAccessToken(for: destination.provider)
            } catch CloudAuthError.missingCredentials where authManager.hasEnvironmentToken(for: destination.provider) {
                guard let envToken = ProcessInfo.processInfo.environment[destination.provider.tokenEnvironmentVariable] else {
                    throw CloudSyncStoreError.providerTokenMissing(destination.provider)
                }
                token = envToken
            }
        } else {
            guard let envToken = ProcessInfo.processInfo.environment[destination.provider.tokenEnvironmentVariable],
                  !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CloudSyncStoreError.providerTokenMissing(destination.provider)
            }
            token = envToken
        }

        switch destination.provider {
        case .googleDrive:
            return GoogleDriveCloudClient(accessToken: token)
        case .dropbox:
            return DropboxCloudClient(accessToken: token)
        case .amazonS3:
            throw CloudSyncStoreError.invalidDestination("S3 client should be initialized via access-key credentials.")
        case .frameIO:
            return FrameIOCloudClient(accessToken: token)
        }
    }

    private func importRemoteFootage(
        assets: [CloudRemoteAsset],
        project: Project,
        existingClips: [Clip],
        destination: CloudSyncDestination,
        client: any CloudStorageProviderClient,
        projectStore: ProjectStore,
        workingDirectory: URL
    ) async throws -> RemoteFootageImportResult {
        guard !assets.isEmpty else {
            return RemoteFootageImportResult(downloadedCount: 0, importedFootageCount: 0, failures: [])
        }

        let footageDirectory = workingDirectory.appendingPathComponent("footage", isDirectory: true)
        try FileManager.default.createDirectory(at: footageDirectory, withIntermediateDirectories: true)

        var downloadedAssets: [(asset: CloudRemoteAsset, localURL: URL)] = []
        var failures: [CloudSyncFailure] = []
        let existingNames = Set(existingClips.map { URL(fileURLWithPath: $0.sourcePath).lastPathComponent.lowercased() })

        for asset in assets {
            let restoredName = restoredRemoteFileName(
                from: asset.name,
                projectName: project.name,
                kind: .footage
            )
            if existingNames.contains(restoredName.lowercased()) {
                continue
            }

            do {
                let localURL = try await downloadRemoteAsset(
                    asset,
                    client: client,
                    workingDirectory: footageDirectory,
                    restoredFileName: restoredName
                )
                downloadedAssets.append((asset, localURL))
            } catch {
                failures.append(.init(assetLabel: asset.name, message: error.localizedDescription))
                try? saveFailedPullRecord(
                    for: asset,
                    destination: destination,
                    projectId: project.id,
                    assetKind: .footage,
                    message: error.localizedDescription
                )
            }
        }

        guard !downloadedAssets.isEmpty else {
            return RemoteFootageImportResult(downloadedCount: 0, importedFootageCount: 0, failures: failures)
        }

        let importResult = try await projectStore.importMedia(
            from: downloadedAssets.map(\.localURL),
            to: project
        )
        let importedByName = Dictionary(
            uniqueKeysWithValues: importResult.importedClips.map { clip in
                (URL(fileURLWithPath: clip.sourcePath).lastPathComponent.lowercased(), clip)
            }
        )
        let failedByName = Dictionary(
            uniqueKeysWithValues: importResult.failedItems.map { error in
                (error.filename.lowercased(), error)
            }
        )

        for downloaded in downloadedAssets {
            let key = downloaded.localURL.lastPathComponent.lowercased()
            if let failure = failedByName[key] {
                failures.append(.init(assetLabel: downloaded.asset.name, message: failure.message))
                try? saveFailedPullRecord(
                    for: downloaded.asset,
                    destination: destination,
                    projectId: project.id,
                    assetKind: .footage,
                    message: failure.message
                )
                continue
            }

            let localPath = importedByName[key]?.sourcePath ?? downloaded.localURL.path
            try saveRecord(
                CloudSyncRecord(
                    projectId: project.id,
                    destinationId: destination.id,
                    provider: destination.provider,
                    assetKind: .footage,
                    assetLabel: "Pulled \(downloaded.asset.name)",
                    localPath: localPath,
                    remoteIdentifier: downloaded.asset.remotePath ?? downloaded.asset.name,
                    remotePath: downloaded.asset.remotePath,
                    remoteURL: downloaded.asset.remoteURL,
                    byteCount: downloaded.asset.byteCount,
                    status: .synced
                )
            )
        }

        return RemoteFootageImportResult(
            downloadedCount: downloadedAssets.count,
            importedFootageCount: importResult.importedClips.count,
            failures: failures
        )
    }

    private func downloadRemoteAsset(
        _ asset: CloudRemoteAsset,
        client: any CloudStorageProviderClient,
        workingDirectory: URL,
        restoredFileName: String
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let localURL = workingDirectory.appendingPathComponent(restoredFileName)
        if FileManager.default.fileExists(atPath: localURL.path) {
            try FileManager.default.removeItem(at: localURL)
        }
        try await client.download(asset: asset, to: localURL)
        return localURL
    }

    private func applyCommentsManifest(at fileURL: URL, projectId: String) throws -> Int {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        let manifest = try JSONDecoder().decode(
            CloudSyncCommentsManifest.self,
            from: Data(contentsOf: fileURL)
        )
        let projectClips = try loadProjectClips(projectId: projectId)
        var updates: [(clipId: String, reviewStatus: ReviewStatus, annotations: [Annotation], approvalStatus: ApprovalStatus, approvedBy: String?, approvedAt: String?, updatedAt: String)] = []

        for entry in manifest.clips {
            guard let clip = findMatchingClip(
                clipId: entry.clipId,
                checksum: entry.checksum,
                fileName: entry.fileName,
                in: projectClips
            ) else {
                continue
            }

            let mergedAnnotations = mergeAnnotations(local: clip.annotations, remote: entry.annotations)
            let remoteIsNewer = isRemoteTimestamp(entry.updatedAt, newerThan: clip.updatedAt)
            let reviewStatus = remoteIsNewer ? (ReviewStatus(rawValue: entry.reviewStatus) ?? clip.reviewStatus) : clip.reviewStatus
            let approvalStatus = remoteIsNewer ? (ApprovalStatus(rawValue: entry.approvalStatus) ?? clip.approvalStatus) : clip.approvalStatus
            let approvedBy = remoteIsNewer ? entry.approvedBy : clip.approvedBy
            let approvedAt = remoteIsNewer ? entry.approvedAt : clip.approvedAt
            let updatedAt = maxTimestamp(entry.updatedAt, clip.updatedAt)

            guard reviewStatus != clip.reviewStatus
                || approvalStatus != clip.approvalStatus
                || approvedBy != clip.approvedBy
                || approvedAt != clip.approvedAt
                || mergedAnnotations != clip.annotations
            else {
                continue
            }

            updates.append((
                clipId: clip.id,
                reviewStatus: reviewStatus,
                annotations: mergedAnnotations,
                approvalStatus: approvalStatus,
                approvedBy: approvedBy,
                approvedAt: approvedAt,
                updatedAt: updatedAt
            ))
        }

        guard !updates.isEmpty else {
            return 0
        }

        try dbQueue.write { db in
            for update in updates {
                try db.execute(
                    sql: """
                        UPDATE clips
                        SET review_status = ?, annotations = ?, approval_status = ?,
                            approved_by = ?, approved_at = ?, updated_at = ?
                        WHERE id = ?
                    """,
                    arguments: [
                        update.reviewStatus.rawValue,
                        try Self.encodeJSON(update.annotations) ?? "[]",
                        update.approvalStatus.rawValue,
                        update.approvedBy,
                        update.approvedAt,
                        update.updatedAt,
                        update.clipId
                    ]
                )
            }
        }

        return updates.count
    }

    private func importAssemblyArchive(
        at fileURL: URL,
        projectId: String,
        clips: [Clip]
    ) throws -> Int {
        let payload = try JSONDecoder().decode(
            CloudSyncAssemblyArchivePayload.self,
            from: Data(contentsOf: fileURL)
        )

        let snapshotsById = Dictionary(uniqueKeysWithValues: payload.clips.map { ($0.clipId, $0) })
        let remappedClips = payload.assembly.clips.compactMap { assemblyClip -> AssemblyClip? in
            let snapshot = snapshotsById[assemblyClip.clipId]
            let matchingClip = findMatchingClip(
                clipId: assemblyClip.clipId,
                checksum: snapshot?.checksum,
                fileName: snapshot?.filename,
                in: clips
            )

            guard let matchingClip else {
                return nil
            }

            return AssemblyClip(
                clipId: matchingClip.id,
                inPoint: assemblyClip.inPoint,
                outPoint: assemblyClip.outPoint,
                role: assemblyClip.role,
                sceneLabel: assemblyClip.sceneLabel
            )
        }

        guard !remappedClips.isEmpty else {
            return 0
        }

        var assembly = payload.assembly
        assembly.projectId = projectId
        assembly.clips = remappedClips

        if let existing = try loadAssembly(id: assembly.id, projectId: projectId),
           existing.version > assembly.version {
            return 0
        }

        try upsertAssembly(assembly)
        return 1
    }

    private func saveFailedPullRecord(
        for asset: CloudRemoteAsset,
        destination: CloudSyncDestination,
        projectId: String,
        assetKind: CloudSyncAssetKind,
        message: String
    ) throws {
        try saveRecord(
            CloudSyncRecord(
                projectId: projectId,
                destinationId: destination.id,
                provider: destination.provider,
                assetKind: assetKind,
                assetLabel: "Pull failed: \(asset.name)",
                localPath: "",
                remoteIdentifier: asset.remotePath ?? asset.name,
                remotePath: asset.remotePath,
                remoteURL: asset.remoteURL,
                byteCount: asset.byteCount,
                status: .failed,
                errorMessage: message
            )
        )
    }

    private func loadProjectClips(projectId: String) throws -> [Clip] {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM clips
                    WHERE project_id = ?
                    ORDER BY updated_at DESC, ingested_at DESC
                """,
                arguments: [projectId]
            )
            .map(Self.decodeClip)
        }
    }

    private func loadAssembly(id: String, projectId: String) throws -> Assembly? {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, project_id, name, mode, clips, created_at, version
                    FROM assemblies
                    WHERE id = ? AND project_id = ?
                    LIMIT 1
                """,
                arguments: [id, projectId]
            ) else {
                return nil
            }

            return Self.decodeAssembly(row)
        }
    }

    private func upsertAssembly(_ assembly: Assembly) throws {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
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
                arguments: [
                    assembly.id,
                    assembly.projectId,
                    assembly.name,
                    assembly.mode.rawValue,
                    try Self.encodeJSON(assembly.clips) ?? "[]",
                    assembly.createdAt,
                    assembly.version
                ]
            )
        }
    }

    private func findMatchingClip(
        clipId: String,
        checksum: String?,
        fileName: String?,
        in clips: [Clip]
    ) -> Clip? {
        if let exactMatch = clips.first(where: { $0.id == clipId }) {
            return exactMatch
        }

        if let checksum,
           let checksumMatch = clips.first(where: { $0.checksum == checksum }) {
            return checksumMatch
        }

        guard let fileName else {
            return nil
        }

        let normalizedName = fileName.lowercased()
        return clips.first {
            URL(fileURLWithPath: $0.sourcePath).lastPathComponent.lowercased() == normalizedName
        }
    }

    private func mergeAnnotations(local: [Annotation], remote: [Annotation]) -> [Annotation] {
        var mergedByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for annotation in remote {
            mergedByID[annotation.id] = annotation
        }

        return mergedByID.values.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.timecodeIn < $1.timecodeIn
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private func remoteAssetKind(for name: String, projectName: String) -> CloudSyncAssetKind? {
        let projectPrefix = sanitizedName(projectName)
        if name == "\(projectPrefix)-comments.json" {
            return .comments
        }
        if name.hasPrefix("\(projectPrefix)-footage-") {
            return .footage
        }
        if name.hasPrefix("\(projectPrefix)-edit-") {
            return .edit
        }
        return nil
    }

    private func restoredRemoteFileName(
        from remoteName: String,
        projectName: String,
        kind: CloudSyncAssetKind
    ) -> String {
        let prefix: String
        switch kind {
        case .footage:
            prefix = "\(sanitizedName(projectName))-footage-"
        case .edit:
            prefix = "\(sanitizedName(projectName))-edit-"
        case .comments:
            prefix = ""
        }

        guard !prefix.isEmpty, remoteName.hasPrefix(prefix) else {
            return remoteName
        }
        return String(remoteName.dropFirst(prefix.count))
    }

    private func remoteAssetSortPredicate(_ lhs: CloudRemoteAsset, _ rhs: CloudRemoteAsset) -> Bool {
        switch (parseTimestamp(lhs.modifiedAt), parseTimestamp(rhs.modifiedAt)) {
        case let (left?, right?) where left != right:
            return left > right
        default:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func maxTimestamp(_ lhs: String, _ rhs: String) -> String {
        guard let lhsDate = parseTimestamp(lhs),
              let rhsDate = parseTimestamp(rhs) else {
            return max(lhs, rhs)
        }
        return lhsDate >= rhsDate ? lhs : rhs
    }

    private func isRemoteTimestamp(_ lhs: String, newerThan rhs: String) -> Bool {
        guard let lhsDate = parseTimestamp(lhs),
              let rhsDate = parseTimestamp(rhs) else {
            return lhs >= rhs
        }
        return lhsDate >= rhsDate
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return ISO8601DateFormatter().date(from: value)
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
            try Self.ensureSchema(in: db)
        }
        dbQueue = queue
    }

    private static func ensureSchema(in db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS cloud_sync_destinations (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                name TEXT NOT NULL,
                configuration_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
        """)

        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS cloud_sync_records (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL,
                destination_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                asset_kind TEXT NOT NULL,
                asset_label TEXT NOT NULL,
                local_path TEXT NOT NULL,
                remote_identifier TEXT,
                remote_path TEXT,
                remote_url TEXT,
                byte_count INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                error_message TEXT,
                synced_at TEXT NOT NULL
            )
        """)

        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cloud_sync_destinations_project_id ON cloud_sync_destinations(project_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cloud_sync_records_project_id ON cloud_sync_records(project_id)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cloud_sync_records_destination_id ON cloud_sync_records(destination_id)")
    }

    private func saveDestination(_ destination: CloudSyncDestination) throws {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        let configurationJSON = try Self.encodeJSON(destination.configuration) ?? "{}"
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cloud_sync_destinations (
                        id, project_id, provider, name, configuration_json, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        project_id = excluded.project_id,
                        provider = excluded.provider,
                        name = excluded.name,
                        configuration_json = excluded.configuration_json,
                        updated_at = excluded.updated_at
                """,
                arguments: [
                    destination.id,
                    destination.projectId,
                    destination.provider.rawValue,
                    destination.name,
                    configurationJSON,
                    destination.createdAt,
                    destination.updatedAt
                ]
            )
        }
    }

    private func saveRecord(_ record: CloudSyncRecord) throws {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO cloud_sync_records (
                        id, project_id, destination_id, provider, asset_kind, asset_label,
                        local_path, remote_identifier, remote_path, remote_url, byte_count,
                        status, error_message, synced_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id,
                    record.projectId,
                    record.destinationId,
                    record.provider.rawValue,
                    record.assetKind.rawValue,
                    record.assetLabel,
                    record.localPath,
                    record.remoteIdentifier,
                    record.remotePath,
                    record.remoteURL,
                    record.byteCount,
                    record.status.rawValue,
                    record.errorMessage,
                    record.syncedAt
                ]
            )
        }
    }

    private func loadDestinations(projectId: String) throws -> [CloudSyncDestination] {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM cloud_sync_destinations
                    WHERE project_id = ?
                    ORDER BY updated_at DESC, created_at DESC
                """,
                arguments: [projectId]
            )
            .compactMap(Self.decodeDestination)
        }
    }

    private func loadRecords(projectId: String) throws -> [CloudSyncRecord] {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM cloud_sync_records
                    WHERE project_id = ?
                    ORDER BY synced_at DESC
                """,
                arguments: [projectId]
            )
            .compactMap(Self.decodeRecord)
        }
    }

    private func loadAssemblies(projectId: String) throws -> [Assembly] {
        guard let dbQueue else {
            throw CloudSyncStoreError.databaseUnavailable
        }

        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, project_id, name, mode, clips, created_at, version
                    FROM assemblies
                    WHERE project_id = ?
                    ORDER BY created_at DESC, version DESC
                """,
                arguments: [projectId]
            )
            .compactMap(Self.decodeAssembly)
        }
    }

    private func loadLatestAssembly(projectId: String) throws -> Assembly? {
        try loadAssemblies(projectId: projectId).first
    }

    private static func decodeClip(_ row: Row) throws -> Clip {
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

    private static func decodeDestination(_ row: Row) -> CloudSyncDestination? {
        guard let provider = CloudSyncProvider(rawValue: row["provider"]) else {
            return nil
        }

        do {
            let configuration = try decodeJSON(row["configuration_json"], as: CloudSyncDestinationConfiguration.self)
                ?? CloudSyncDestinationConfiguration()
            return CloudSyncDestination(
                id: row["id"],
                projectId: row["project_id"],
                provider: provider,
                name: row["name"],
                configuration: configuration,
                createdAt: row["created_at"],
                updatedAt: row["updated_at"]
            )
        } catch {
            return nil
        }
    }

    private static func decodeRecord(_ row: Row) -> CloudSyncRecord? {
        guard let provider = CloudSyncProvider(rawValue: row["provider"]),
              let assetKind = CloudSyncAssetKind(rawValue: row["asset_kind"]),
              let status = CloudSyncRecordStatus(rawValue: row["status"]) else {
            return nil
        }

        return CloudSyncRecord(
            id: row["id"],
            projectId: row["project_id"],
            destinationId: row["destination_id"],
            provider: provider,
            assetKind: assetKind,
            assetLabel: row["asset_label"],
            localPath: row["local_path"],
            remoteIdentifier: row["remote_identifier"],
            remotePath: row["remote_path"],
            remoteURL: row["remote_url"],
            byteCount: row["byte_count"],
            status: status,
            errorMessage: row["error_message"],
            syncedAt: row["synced_at"]
        )
    }

    private static func decodeAssembly(_ row: Row) -> Assembly? {
        guard let mode = ProjectMode(rawValue: row["mode"]) else {
            return nil
        }

        do {
            let clips = try decodeJSON(row["clips"], as: [AssemblyClip].self) ?? []
            return Assembly(
                id: row["id"],
                projectId: row["project_id"],
                name: row["name"],
                mode: mode,
                clips: clips,
                createdAt: row["created_at"],
                version: row["version"]
            )
        } catch {
            return nil
        }
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

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func sanitizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        return replaced.isEmpty ? "slate-project" : replaced
    }
}

private protocol CloudStorageProviderClient: Sendable {
    func upload(
        fileURL: URL,
        remoteName: String,
        destination: CloudSyncDestination
    ) async throws -> ProviderUploadResult
    func listAssets(destination: CloudSyncDestination) async throws -> [CloudRemoteAsset]
    func download(asset: CloudRemoteAsset, to localURL: URL) async throws
}

private struct GoogleDriveCloudClient: CloudStorageProviderClient {
    let accessToken: String

    func upload(
        fileURL: URL,
        remoteName: String,
        destination: CloudSyncDestination
    ) async throws -> ProviderUploadResult {
        guard let folderId = destination.configuration.remoteFolderId else {
            throw CloudSyncStoreError.invalidDestination("Google Drive destinations need a folder ID.")
        }

        let mimeType = fileURL.detectedMimeType
        let fileSize = try fileURL.byteCount
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&supportsAllDrives=true&fields=id,name,webViewLink,size")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mimeType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")

        let metadata = [
            "name": remoteName,
            "parents": [folderId]
        ] as [String : Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let sessionURLString = httpResponse.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: sessionURLString) else {
            throw CloudSyncStoreError.uploadFailed("Google Drive did not return a resumable upload session.")
        }

        var uploadRequest = URLRequest(url: sessionURL)
        uploadRequest.httpMethod = "PUT"
        uploadRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        uploadRequest.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        let (uploadData, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, fromFile: fileURL)
        guard let uploadHTTPResponse = uploadResponse as? HTTPURLResponse,
              (200..<300).contains(uploadHTTPResponse.statusCode) else {
            throw CloudSyncStoreError.uploadFailed("Google Drive rejected the file upload for \(remoteName).")
        }

        let payload = try JSONDecoder().decode(GoogleDriveFilePayload.self, from: uploadData)
        return ProviderUploadResult(
            remoteIdentifier: payload.id,
            remotePath: folderId,
            remoteURL: payload.webViewLink,
            byteCount: Int64(payload.size ?? "") ?? fileSize
        )
    }

    func listAssets(destination: CloudSyncDestination) async throws -> [CloudRemoteAsset] {
        guard let folderId = destination.configuration.remoteFolderId else {
            throw CloudSyncStoreError.invalidDestination("Google Drive destinations need a folder ID.")
        }

        var assets: [CloudRemoteAsset] = []
        var pageToken: String?

        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            var queryItems: [URLQueryItem] = [
                .init(name: "q", value: "'\(folderId)' in parents and trashed = false"),
                .init(name: "fields", value: "nextPageToken,files(id,name,size,modifiedTime,webViewLink,mimeType)"),
                .init(name: "pageSize", value: "200"),
                .init(name: "supportsAllDrives", value: "true"),
                .init(name: "includeItemsFromAllDrives", value: "true")
            ]
            if let pageToken {
                queryItems.append(.init(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, data: data, context: "Google Drive list")

            let payload = try JSONDecoder().decode(GoogleDriveListResponse.self, from: data)
            assets.append(contentsOf: payload.files.compactMap { file in
                guard file.mimeType != "application/vnd.google-apps.folder" else {
                    return nil
                }
                return CloudRemoteAsset(
                    name: file.name,
                    locator: .googleFile(file.id),
                    remotePath: file.id,
                    remoteURL: file.webViewLink,
                    byteCount: Int64(file.size ?? "") ?? 0,
                    modifiedAt: file.modifiedTime
                )
            })
            pageToken = payload.nextPageToken
        } while pageToken != nil

        return assets
    }

    func download(asset: CloudRemoteAsset, to localURL: URL) async throws {
        guard case .googleFile(let fileId) = asset.locator else {
            throw CloudSyncStoreError.uploadFailed("Google Drive could not resolve the selected file.")
        }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        components.queryItems = [
            .init(name: "alt", value: "media"),
            .init(name: "supportsAllDrives", value: "true")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        try validateHTTPResponse(response, context: "Google Drive download")
        try moveDownloadedFile(from: temporaryURL, to: localURL)
    }
}

private struct DropboxCloudClient: CloudStorageProviderClient {
    let accessToken: String
    private let chunkSize = 8 * 1024 * 1024

    func upload(
        fileURL: URL,
        remoteName: String,
        destination: CloudSyncDestination
    ) async throws -> ProviderUploadResult {
        guard let basePath = destination.configuration.remotePath else {
            throw CloudSyncStoreError.invalidDestination("Dropbox destinations need a folder path.")
        }

        let normalizedBasePath = basePath.hasPrefix("/") ? basePath : "/\(basePath)"
        try await ensureDropboxFolder(normalizedBasePath)

        let remotePath = "\(normalizedBasePath)/\(remoteName)"
        let fileSize = try fileURL.byteCount

        let metadata: DropboxFileMetadata
        if fileSize <= 150 * 1024 * 1024 {
            metadata = try await uploadSmallFile(fileURL: fileURL, remotePath: remotePath)
        } else {
            metadata = try await uploadLargeFile(fileURL: fileURL, remotePath: remotePath, fileSize: fileSize)
        }

        let sharedURL = try await createDropboxSharedLink(remotePath: remotePath)
        return ProviderUploadResult(
            remoteIdentifier: metadata.id,
            remotePath: metadata.pathDisplay ?? remotePath,
            remoteURL: sharedURL,
            byteCount: Int64(metadata.size)
        )
    }

    private func uploadSmallFile(fileURL: URL, remotePath: String) async throws -> DropboxFileMetadata {
        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(
            #"{"path":"\#(remotePath)","mode":"overwrite","autorename":false,"mute":true,"strict_conflict":false}"#,
            forHTTPHeaderField: "Dropbox-API-Arg"
        )

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CloudSyncStoreError.uploadFailed("Dropbox rejected the upload for \(remotePath).")
        }

        return try JSONDecoder.dropbox.decode(DropboxFileMetadata.self, from: data)
    }

    private func uploadLargeFile(fileURL: URL, remotePath: String, fileSize: Int64) async throws -> DropboxFileMetadata {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        let firstChunk = try fileHandle.read(upToCount: chunkSize) ?? Data()
        guard !firstChunk.isEmpty else {
            throw CloudSyncStoreError.uploadFailed("Dropbox could not read the source file for \(remotePath).")
        }

        var startRequest = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload_session/start")!)
        startRequest.httpMethod = "POST"
        startRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        startRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        startRequest.setValue(#"{"close":false}"#, forHTTPHeaderField: "Dropbox-API-Arg")
        let (startData, startResponse) = try await URLSession.shared.upload(for: startRequest, from: firstChunk)
        guard let startHTTPResponse = startResponse as? HTTPURLResponse,
              (200..<300).contains(startHTTPResponse.statusCode) else {
            throw CloudSyncStoreError.uploadFailed("Dropbox could not start an upload session.")
        }

        let session = try JSONDecoder.dropbox.decode(DropboxUploadSession.self, from: startData)
        var offset = Int64(firstChunk.count)

        while offset < fileSize {
            let remainingBytes = fileSize - offset
            let currentChunkSize = Int(min(Int64(chunkSize), remainingBytes))
            let chunk = try fileHandle.read(upToCount: currentChunkSize) ?? Data()
            guard !chunk.isEmpty else {
                break
            }

            if offset + Int64(chunk.count) < fileSize {
                var appendRequest = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload_session/append_v2")!)
                appendRequest.httpMethod = "POST"
                appendRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                appendRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                appendRequest.setValue(
                    #"{"cursor":{"session_id":"\#(session.sessionId)","offset":\#(offset)},"close":false}"#,
                    forHTTPHeaderField: "Dropbox-API-Arg"
                )
                let (_, appendResponse) = try await URLSession.shared.upload(for: appendRequest, from: chunk)
                guard let appendHTTPResponse = appendResponse as? HTTPURLResponse,
                      (200..<300).contains(appendHTTPResponse.statusCode) else {
                    throw CloudSyncStoreError.uploadFailed("Dropbox failed while appending upload chunks.")
                }
                offset += Int64(chunk.count)
            } else {
                var finishRequest = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload_session/finish")!)
                finishRequest.httpMethod = "POST"
                finishRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                finishRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                finishRequest.setValue(
                    #"{"cursor":{"session_id":"\#(session.sessionId)","offset":\#(offset)},"commit":{"path":"\#(remotePath)","mode":"overwrite","autorename":false,"mute":true,"strict_conflict":false}}"#,
                    forHTTPHeaderField: "Dropbox-API-Arg"
                )
                let (finishData, finishResponse) = try await URLSession.shared.upload(for: finishRequest, from: chunk)
                guard let finishHTTPResponse = finishResponse as? HTTPURLResponse,
                      (200..<300).contains(finishHTTPResponse.statusCode) else {
                    throw CloudSyncStoreError.uploadFailed("Dropbox could not finish the upload session.")
                }
                return try JSONDecoder.dropbox.decode(DropboxFileMetadata.self, from: finishData)
            }
        }

        throw CloudSyncStoreError.uploadFailed("Dropbox upload ended before the file was committed.")
    }

    private func ensureDropboxFolder(_ path: String) async throws {
        let segments = path.split(separator: "/").map(String.init)
        guard !segments.isEmpty else { return }

        var currentPath = ""
        for segment in segments {
            currentPath += "/\(segment)"
            var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/create_folder_v2")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "path": currentPath,
                "autorename": false
            ])

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }

            // 200 = created, 409 = already exists.
            if (200..<300).contains(httpResponse.statusCode) || httpResponse.statusCode == 409 {
                continue
            }

            throw CloudSyncStoreError.uploadFailed("Dropbox could not prepare the folder \(currentPath).")
        }
    }

    private func createDropboxSharedLink(remotePath: String) async throws -> String? {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": remotePath,
            "settings": [
                "requested_visibility": "public"
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            return nil
        }

        if (200..<300).contains(httpResponse.statusCode) {
            return try? JSONDecoder.dropbox.decode(DropboxSharedLinkResponse.self, from: data).url
        }

        return nil
    }

    func listAssets(destination: CloudSyncDestination) async throws -> [CloudRemoteAsset] {
        guard let path = destination.configuration.remotePath else {
            throw CloudSyncStoreError.invalidDestination("Dropbox destinations need a folder path.")
        }

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": path,
            "recursive": false,
            "include_deleted": false
        ])

        var assets: [CloudRemoteAsset] = []
        var (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, context: "Dropbox list")
        var payload = try JSONDecoder.dropbox.decode(DropboxListFolderResponse.self, from: data)
        assets.append(contentsOf: payload.entries.compactMap { entry in
            guard entry.tag == "file" else {
                return nil
            }
            return CloudRemoteAsset(
                name: entry.name,
                locator: .dropboxPath(entry.pathDisplay ?? entry.pathLower ?? entry.id),
                remotePath: entry.pathDisplay ?? entry.pathLower,
                remoteURL: nil,
                byteCount: Int64(entry.size ?? 0),
                modifiedAt: entry.clientModified
            )
        })

        while payload.hasMore {
            var continueRequest = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/list_folder/continue")!)
            continueRequest.httpMethod = "POST"
            continueRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            continueRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            continueRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "cursor": payload.cursor
            ])

            (data, response) = try await URLSession.shared.data(for: continueRequest)
            try validateHTTPResponse(response, data: data, context: "Dropbox list continuation")
            payload = try JSONDecoder.dropbox.decode(DropboxListFolderResponse.self, from: data)
            assets.append(contentsOf: payload.entries.compactMap { entry in
                guard entry.tag == "file" else {
                    return nil
                }
                return CloudRemoteAsset(
                    name: entry.name,
                    locator: .dropboxPath(entry.pathDisplay ?? entry.pathLower ?? entry.id),
                    remotePath: entry.pathDisplay ?? entry.pathLower,
                    remoteURL: nil,
                    byteCount: Int64(entry.size ?? 0),
                    modifiedAt: entry.clientModified
                )
            })
        }

        return assets
    }

    func download(asset: CloudRemoteAsset, to localURL: URL) async throws {
        guard case .dropboxPath(let path) = asset.locator else {
            throw CloudSyncStoreError.uploadFailed("Dropbox could not resolve the selected file.")
        }

        var request = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(#"{"path":"\#(path)"}"#, forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, context: "Dropbox download")
        try data.write(to: localURL, options: .atomic)
    }
}

private struct S3CompatibleCloudClient: CloudStorageProviderClient {
    let accessKeyId: String
    let secretAccessKey: String
    let bucket: String
    let endpoint: String
    let region: String

    func upload(
        fileURL: URL,
        remoteName: String,
        destination: CloudSyncDestination
    ) async throws -> ProviderUploadResult {
        guard let prefix = destination.configuration.remotePath?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty else {
            throw CloudSyncStoreError.invalidDestination("S3 destinations need a remote path prefix.")
        }
        let objectKey = normalizedObjectKey(prefix: prefix, remoteName: remoteName)
        let data = try Data(contentsOf: fileURL)
        let mimeType = fileURL.detectedMimeType
        _ = try await performSignedRequest(method: "PUT", objectKey: objectKey, query: [], body: data, contentType: mimeType)
        let remoteURL = "\(trimmedEndpoint())/\(bucket)/\(objectKey)"
        return ProviderUploadResult(
            remoteIdentifier: objectKey,
            remotePath: prefix,
            remoteURL: remoteURL,
            byteCount: Int64(data.count)
        )
    }

    func listAssets(destination: CloudSyncDestination) async throws -> [CloudRemoteAsset] {
        guard let prefix = destination.configuration.remotePath?.trimmingCharacters(in: .whitespacesAndNewlines), !prefix.isEmpty else {
            return []
        }
        let (_, body) = try await performSignedRequest(
            method: "GET",
            objectKey: "",
            query: [URLQueryItem(name: "list-type", value: "2"), URLQueryItem(name: "prefix", value: prefix)],
            body: Data(),
            contentType: "application/xml"
        )
        guard let xml = String(data: body, encoding: .utf8), !xml.isEmpty else {
            return []
        }
        let keyRegex = try NSRegularExpression(pattern: "<Key>([^<]+)</Key>")
        let sizeRegex = try NSRegularExpression(pattern: "<Size>([0-9]+)</Size>")
        let nsXml = xml as NSString
        let keyMatches = keyRegex.matches(in: xml, range: NSRange(location: 0, length: nsXml.length))
        let sizeMatches = sizeRegex.matches(in: xml, range: NSRange(location: 0, length: nsXml.length))

        var assets: [CloudRemoteAsset] = []
        for (index, keyMatch) in keyMatches.enumerated() {
            guard keyMatch.numberOfRanges > 1 else { continue }
            let key = nsXml.substring(with: keyMatch.range(at: 1))
            let size = (index < sizeMatches.count && sizeMatches[index].numberOfRanges > 1)
                ? Int64(nsXml.substring(with: sizeMatches[index].range(at: 1))) ?? 0
                : 0
            assets.append(
                CloudRemoteAsset(
                    name: URL(fileURLWithPath: key).lastPathComponent,
                    locator: .directURL(URL(string: "\(trimmedEndpoint())/\(bucket)/\(key)")!),
                    remotePath: key,
                    remoteURL: "\(trimmedEndpoint())/\(bucket)/\(key)",
                    byteCount: size,
                    modifiedAt: nil
                )
            )
        }
        return assets
    }

    func download(asset: CloudRemoteAsset, to localURL: URL) async throws {
        switch asset.locator {
        case .directURL(let url):
            let (data, response) = try await URLSession.shared.data(from: url)
            try validateHTTPResponse(response, data: data, context: "S3 download")
            try data.write(to: localURL, options: .atomic)
        default:
            guard let key = asset.remotePath else {
                throw CloudSyncStoreError.uploadFailed("S3 asset key is missing.")
            }
            let (_, data) = try await performSignedRequest(
                method: "GET",
                objectKey: key,
                query: [],
                body: Data(),
                contentType: "application/octet-stream"
            )
            try data.write(to: localURL, options: .atomic)
        }
    }

    private func performSignedRequest(
        method: String,
        objectKey: String,
        query: [URLQueryItem],
        body: Data,
        contentType: String
    ) async throws -> (HTTPURLResponse, Data) {
        let host = URL(string: trimmedEndpoint())?.host ?? ""
        let path = "/\(bucket)/\(objectKey.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        let payloadHash = sha256Hex(body)
        let now = Date()
        let amzDate = dateString(now, format: "yyyyMMdd'T'HHmmss'Z'")
        let dateStamp = dateString(now, format: "yyyyMMdd")
        let signedHeaders = "content-length;content-type;host;x-amz-content-sha256;x-amz-date"
        let canonicalHeaders = [
            "content-length:\(body.count)",
            "content-type:\(contentType)",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ].joined(separator: "\n") + "\n"
        let canonicalQuery = canonicalQueryString(query)
        let canonicalRequest = [
            method,
            path,
            canonicalQuery,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")
        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")
        let signingKey = deriveSigningKey(secret: secretAccessKey, dateStamp: dateStamp, region: region, service: "s3")
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8)).map { String(format: "%02x", $0) }.joined()
        let authorization = "AWS4-HMAC-SHA256 Credential=\(accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        let queryString = canonicalQuery
        let url = URL(string: "\(trimmedEndpoint())\(path)\(queryString.isEmpty ? "" : "?\(queryString)")")!

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudSyncStoreError.uploadFailed("S3 returned no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CloudSyncStoreError.uploadFailed("S3 request failed: \(body)")
        }
        return (http, data)
    }

    private func normalizedObjectKey(prefix: String, remoteName: String) -> String {
        let left = prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(left)/\(remoteName)"
    }

    private func trimmedEndpoint() -> String {
        endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func dateString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func canonicalQueryString(_ query: [URLQueryItem]) -> String {
        guard !query.isEmpty else { return "" }
        let encodedPairs: [(String, String)] = query.map { item in
            (awsEncode(item.name), awsEncode(item.value ?? ""))
        }
        let sortedPairs = encodedPairs.sorted { lhs, rhs in
            if lhs.0 == rhs.0 {
                return lhs.1 < rhs.1
            }
            return lhs.0 < rhs.0
        }
        let parts = sortedPairs.map { pair in
            "\(pair.0)=\(pair.1)"
        }
        return parts.joined(separator: "&")
    }

    private func awsEncode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"), UInt8(ascii: "/"):
                out.append(Character(UnicodeScalar(byte)))
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let key = SymmetricKey(data: key)
        return Data(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private func deriveSigningKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        let secretData = Data("AWS4\(secret)".utf8)
        let dateKey = hmacSHA256(key: secretData, data: Data(dateStamp.utf8))
        let regionKey = hmacSHA256(key: dateKey, data: Data(region.utf8))
        let serviceKey = hmacSHA256(key: regionKey, data: Data(service.utf8))
        return hmacSHA256(key: serviceKey, data: Data("aws4_request".utf8))
    }
}

private struct FrameIOCloudClient: CloudStorageProviderClient {
    let accessToken: String

    func upload(
        fileURL: URL,
        remoteName: String,
        destination: CloudSyncDestination
    ) async throws -> ProviderUploadResult {
        guard let accountId = destination.configuration.accountId,
              let folderId = destination.configuration.remoteFolderId else {
            throw CloudSyncStoreError.invalidDestination("Frame.io destinations need an account ID and folder ID.")
        }

        let fileSize = try fileURL.byteCount
        var request = URLRequest(
            url: URL(string: "https://api.frame.io/v4/accounts/\(accountId)/folders/\(folderId)/files/local_upload")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "data": [
                "name": remoteName,
                "file_size": fileSize
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CloudSyncStoreError.uploadFailed("Frame.io did not accept the upload request for \(remoteName).")
        }

        let createResponse = try JSONDecoder.frameIO.decode(FrameIOCreateUploadResponse.self, from: data)
        let mimeType = createResponse.data.mediaType ?? fileURL.detectedMimeType
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        for uploadPart in createResponse.data.uploadURLs {
            let chunk = try fileHandle.read(upToCount: uploadPart.size) ?? Data()
            var uploadRequest = URLRequest(url: uploadPart.url)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            uploadRequest.setValue("private", forHTTPHeaderField: "x-amz-acl")
            let (_, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, from: chunk)
            guard let uploadHTTPResponse = uploadResponse as? HTTPURLResponse,
                  (200..<300).contains(uploadHTTPResponse.statusCode) else {
                throw CloudSyncStoreError.uploadFailed("Frame.io failed while uploading \(remoteName).")
            }
        }

        return ProviderUploadResult(
            remoteIdentifier: createResponse.data.id,
            remotePath: folderId,
            remoteURL: createResponse.data.viewURL,
            byteCount: Int64(createResponse.data.fileSize)
        )
    }

    func listAssets(destination: CloudSyncDestination) async throws -> [CloudRemoteAsset] {
        guard let accountId = destination.configuration.accountId,
              let folderId = destination.configuration.remoteFolderId else {
            throw CloudSyncStoreError.invalidDestination("Frame.io destinations need an account ID and folder ID.")
        }

        var nextURL: URL? = URL(string: "https://api.frame.io/v4/accounts/\(accountId)/folders/\(folderId)/children?page_size=200")
        var assets: [CloudRemoteAsset] = []

        while let currentURL = nextURL {
            var request = URLRequest(url: currentURL)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, data: data, context: "Frame.io list")

            let payload = try JSONDecoder.frameIO.decode(FrameIOChildrenResponse.self, from: data)
            assets.append(contentsOf: payload.data.compactMap { entry in
                guard entry.type == "file" else {
                    return nil
                }
                let locator: CloudRemoteLocator
                if let downloadURL = entry.mediaLinks?.original?.downloadURL.flatMap(URL.init(string:)) {
                    locator = .directURL(downloadURL)
                } else {
                    locator = .frameIOFile(accountId: accountId, fileId: entry.id)
                }

                return CloudRemoteAsset(
                    name: entry.name,
                    locator: locator,
                    remotePath: entry.parentId,
                    remoteURL: entry.viewURL,
                    byteCount: Int64(entry.fileSize ?? 0),
                    modifiedAt: entry.updatedAt
                )
            })

            if let nextPath = payload.links?.next, !nextPath.isEmpty {
                nextURL = URL(string: nextPath, relativeTo: URL(string: "https://api.frame.io"))?.absoluteURL
            } else {
                nextURL = nil
            }
        }

        return assets
    }

    func download(asset: CloudRemoteAsset, to localURL: URL) async throws {
        let requestURL: URL
        switch asset.locator {
        case .directURL(let url):
            requestURL = url
        case .frameIOFile(let accountId, let fileId):
            requestURL = URL(string: "https://api.frame.io/v4/accounts/\(accountId)/files/\(fileId)")!
        default:
            throw CloudSyncStoreError.uploadFailed("Frame.io could not resolve the selected file.")
        }

        if case .frameIOFile = asset.locator {
            var metadataRequest = URLRequest(url: requestURL)
            metadataRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            metadataRequest.setValue("experimental", forHTTPHeaderField: "api-version")
            let (metadataData, metadataResponse) = try await URLSession.shared.data(for: metadataRequest)
            try validateHTTPResponse(metadataResponse, data: metadataData, context: "Frame.io file lookup")
            let metadata = try JSONDecoder.frameIO.decode(FrameIOFileResponse.self, from: metadataData)

            if let downloadURL = metadata.data.directDownloadURL {
                try await downloadFromDirectURL(downloadURL, to: localURL)
                return
            }

            throw CloudSyncStoreError.uploadFailed("Frame.io did not return a downloadable media link for \(asset.name).")
        }

        try await downloadFromDirectURL(requestURL, to: localURL)
    }

    private func downloadFromDirectURL(_ url: URL, to localURL: URL) async throws {
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        try validateHTTPResponse(response, context: "Frame.io download")
        try moveDownloadedFile(from: temporaryURL, to: localURL)
    }
}

private struct GoogleDriveFilePayload: Decodable {
    let id: String
    let name: String
    let webViewLink: String?
    let size: String?
}

private struct GoogleDriveListResponse: Decodable {
    struct File: Decodable {
        let id: String
        let name: String
        let size: String?
        let modifiedTime: String?
        let webViewLink: String?
        let mimeType: String?
    }

    let nextPageToken: String?
    let files: [File]
}

private struct DropboxUploadSession: Decodable {
    let sessionId: String
}

private struct DropboxFileMetadata: Decodable {
    let id: String
    let pathDisplay: String?
    let size: Int
}

private struct DropboxSharedLinkResponse: Decodable {
    let url: String
}

private struct DropboxListFolderResponse: Decodable {
    struct Entry: Decodable {
        let tag: String
        let id: String
        let name: String
        let pathDisplay: String?
        let pathLower: String?
        let size: Int?
        let clientModified: String?

        enum CodingKeys: String, CodingKey {
            case tag = ".tag"
            case id
            case name
            case pathDisplay
            case pathLower
            case size
            case clientModified
        }
    }

    let entries: [Entry]
    let cursor: String
    let hasMore: Bool
}

private struct FrameIOCreateUploadResponse: Decodable {
    struct Payload: Decodable {
        struct UploadPart: Decodable {
            let size: Int
            let url: URL
        }

        let id: String
        let fileSize: Int
        let mediaType: String?
        let viewURL: String?
        let uploadURLs: [UploadPart]
    }

    let data: Payload
}

private struct FrameIOChildrenResponse: Decodable {
    struct Links: Decodable {
        let next: String?
    }

    struct Entry: Decodable {
        struct MediaLinks: Decodable {
            struct Variant: Decodable {
                let downloadURL: String?
            }

            let original: Variant?
        }

        let id: String
        let name: String
        let type: String?
        let fileSize: Int?
        let updatedAt: String?
        let parentId: String?
        let viewURL: String?
        let mediaLinks: MediaLinks?
    }

    let data: [Entry]
    let links: Links?
}

private struct FrameIOFileResponse: Decodable {
    struct Payload: Decodable {
        struct MediaLinks: Decodable {
            struct Variant: Decodable {
                let downloadURL: String?
            }

            let original: Variant?
            let downloadURL: String?
        }

        let downloadURL: String?
        let mediaLinks: MediaLinks?

        var directDownloadURL: URL? {
            if let downloadURL,
               let url = URL(string: downloadURL) {
                return url
            }

            if let mediaLinkURL = mediaLinks?.downloadURL,
               let url = URL(string: mediaLinkURL) {
                return url
            }

            if let originalURL = mediaLinks?.original?.downloadURL,
               let url = URL(string: originalURL) {
                return url
            }

            return nil
        }
    }

    let data: Payload
}

private extension JSONDecoder {
    static var dropbox: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var frameIO: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension URL {
    var byteCount: Int64 {
        get throws {
            let values = try resourceValues(forKeys: [.fileSizeKey])
            return Int64(values.fileSize ?? 0)
        }
    }

    var detectedMimeType: String {
        if let type = UTType(filenameExtension: pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }

        return "application/octet-stream"
    }
}

private func validateHTTPResponse(
    _ response: URLResponse,
    data: Data? = nil,
    context: String
) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw CloudSyncStoreError.uploadFailed("\(context) returned no HTTP response.")
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
        let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(httpResponse.statusCode)"
        throw CloudSyncStoreError.uploadFailed("\(context) failed: \(message)")
    }
}

private func moveDownloadedFile(from sourceURL: URL, to destinationURL: URL) throws {
    let fileManager = FileManager.default
    let destinationDirectory = destinationURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.moveItem(at: sourceURL, to: destinationURL)
}
