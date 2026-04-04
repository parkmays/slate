// SLATE — IngestDaemon
// Owned by: Claude Code
//
// Minimal ingest wiring that persists the canonical Clip model and invokes
// Codex-owned sync + AI scoring after ingest discovers external audio.

import CryptoKit
import Foundation
import SLATEAIPipeline
import SLATESharedTypes
import SLATESyncEngine

// MARK: - SyncEngine type bridges

private extension MultiCamSyncMethod {
    /// Maps the sync-engine's MultiCamSyncMethod to the shared SyncMethod used on Clip.
    var asSyncMethod: SyncMethod {
        switch self {
        case .waveformCorrelation: return .waveformCorrelation
        case .timecode:            return .timecode
        case .manual:              return .manual
        }
    }
}

private extension SyncConfidence {
    /// SyncConfidence lives in SLATESharedTypes; the sync-engine reuses it directly.
    /// This no-op extension just makes intent explicit at call sites.
    var asSharedConfidence: SyncConfidence { self }
}

public typealias WatchFolderConfig = WatchFolder

private let supportedMediaExtensions: Set<String> = [
    "ari", "arx", "braw", "mov", "mp4", "mxf", "r3d"
]

private let supportedAudioExtensions: Set<String> = [
    "aif", "aiff", "caf", "m4a", "mp3", "wav"
]

public enum IngestDaemonError: Error, LocalizedError {
    case fileTooSmall(path: String, size: Int64)
    case unsupportedFormat(path: String)
    case noWatchFolder(path: String)

    public var errorDescription: String? {
        switch self {
        case .fileTooSmall(let path, let size):
            return "File too small (\(size) bytes): \(path)"
        case .unsupportedFormat(let path):
            return "Unsupported format: \(path)"
        case .noWatchFolder(let path):
            return "No watch folder registered for \(path)"
        }
    }
}

public actor IngestPipeline {
    private let watchConfig: WatchFolderConfig
    private let store: GRDBStore
    private let onProgress: @Sendable (IngestProgressItem) -> Void

    public init(
        watchConfig: WatchFolderConfig,
        store: GRDBStore = .shared,
        onProgress: @escaping @Sendable (IngestProgressItem) -> Void = { _ in }
    ) {
        self.watchConfig = watchConfig
        self.store = store
        self.onProgress = onProgress
    }

    public func ingest(sourceURL: URL) async throws -> Clip {
        let pathExtension = sourceURL.pathExtension.lowercased()
        guard supportedMediaExtensions.contains(pathExtension) else {
            throw IngestDaemonError.unsupportedFormat(path: sourceURL.path)
        }

        let fileSize = try sourceFileSize(at: sourceURL)
        guard fileSize >= 1_000_000 else {
            throw IngestDaemonError.fileTooSmall(path: sourceURL.path, size: fileSize)
        }

        // Create initial clip and queue item
        let checksum = try ChecksumUtil.sha256(fileURL: sourceURL)
        
        if let existing = try await store.getClip(byChecksum: checksum) {
            return existing
        }

        let clip = buildClip(sourceURL: sourceURL, checksum: checksum, fileSize: fileSize)
        
        // Extract camera metadata
        let cameraMetadata = CameraMetadataExtractor.extract(from: sourceURL)
        
        var clipWithMetadata = clip
        clipWithMetadata.cameraMetadata = cameraMetadata
        
        try await store.saveClip(clipWithMetadata)
        
        // Create ingest queue item
        let queueItem = GRDBStore.IngestQueueItem(
            clipId: clip.id,
            sourcePath: sourceURL.path,
            destinationPath: clip.proxyPath ?? "",
            stage: .queued
        )
        try await store.addToIngestQueue(queueItem)

        // Stage 1: Checksumming
        report(filename: sourceURL.lastPathComponent, progress: 0.10, stage: .checksum)
        try await store.updateIngestQueueStage(id: queueItem.id, stage: .checksumming, startedAt: Date())
        
        // Verify checksum already done above
        try await store.updateIngestQueueStage(id: queueItem.id, stage: .syncPending, startedAt: Date())

        // Stage 2: Sync
        report(filename: sourceURL.lastPathComponent, progress: 0.55, stage: .sync)
        try await store.updateIngestQueueStage(id: queueItem.id, stage: .syncPending, startedAt: Date())

        let audioFiles = findExternalAudioFiles(near: sourceURL)
        let audioTracks = await SyncEngine().assignAudioRoles(tracks: audioFiles)
        let syncedAudioPath = audioFiles.first?.path
        var syncResult: SyncResult

        // If this clip belongs to a camera group, run multi-cam sync across all angles.
        // Otherwise fall back to single-clip audio sync.
        if let groupId = clip.cameraGroupId, let angle = clip.cameraAngle {
            let groupClips = (try? await store.fetchClips(cameraGroupId: groupId)) ?? []
            let cameras: [CameraInput] = groupClips.compactMap { gc in
                guard let a = gc.cameraAngle, let cameraAngle = CameraAngle(rawValue: a) else { return nil }
                return CameraInput(url: URL(fileURLWithPath: gc.sourcePath), angle: cameraAngle, clipId: gc.id)
            }
            if cameras.count >= 2 {
                let groupResult = try await SyncEngine().syncCameraGroup(
                    cameras: cameras,
                    audioFiles: audioFiles,
                    fps: clip.sourceFps,
                    groupId: groupId
                )
                // Extract this clip's offset from the group result and bridge to SyncResult.
                let myAngle = CameraAngle(rawValue: angle) ?? .A
                let myOffset = groupResult.offsets.first { $0.angle == myAngle }
                syncResult = SyncResult(
                    confidence: (myOffset?.confidence ?? groupResult.overallConfidence).asSharedConfidence,
                    method: (myOffset?.method ?? .waveformCorrelation).asSyncMethod,
                    offsetFrames: myOffset?.offsetFrames ?? 0,
                    driftPPM: 0
                )
            } else {
                syncResult = try await SyncEngine().syncClip(videoURL: sourceURL, audioFiles: audioFiles, fps: clip.sourceFps)
            }
        } else {
            syncResult = try await SyncEngine().syncClip(videoURL: sourceURL, audioFiles: audioFiles, fps: clip.sourceFps)
        }

        try await store.updateAudioSync(
            clipId: clip.id,
            audioTracks: audioTracks,
            syncResult: syncResult,
            syncedAudioPath: syncedAudioPath
        )

        // Stage 3: Proxy generation
        report(filename: sourceURL.lastPathComponent, progress: 0.80, stage: .proxy)
        try await store.updateIngestQueueStage(id: queueItem.id, stage: .proxyPending, startedAt: Date())

        var proxyClip = clipWithMetadata
        proxyClip.audioTracks = audioTracks
        proxyClip.syncResult = syncResult
        proxyClip.syncedAudioPath = syncedAudioPath
        let proxyGenerator = ProxyGenerator(dbQueue: try await store.dbQueue)
        try await proxyGenerator.generateProxy(for: proxyClip)

        try await store.updateIngestQueueStage(id: queueItem.id, stage: .ready, startedAt: Date())

        // Stage 4: AI Analysis
        try await store.updateAIProcessingStatus(clipId: clip.id, status: .processing)

        var scoringClip = clip
        scoringClip.audioTracks = audioTracks
        scoringClip.syncResult = syncResult
        scoringClip.syncedAudioPath = syncedAudioPath
        scoringClip.aiProcessingStatus = .processing
        let scoringInput = scoringClip

        let analysis = try await AIPipeline().analyzeClip(scoringInput)
        let scores = analysis.aiScores
        let transcript = analysis.transcript

        try await store.updateAIScores(clipId: clip.id, aiScores: scores, status: .ready)

        if let transcript = transcript {
            try await store.saveTranscript(transcript, forClipId: clip.id)
        }

        report(filename: sourceURL.lastPathComponent, progress: 1.0, stage: .complete)
        if let persistedClip = try await store.getClip(byId: clip.id) {
            return persistedClip
        }

        scoringClip.aiScores = scores
        scoringClip.aiProcessingStatus = .ready
        return scoringClip
    }

    private func buildClip(sourceURL: URL, checksum: String, fileSize: Int64) -> Clip {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return Clip(
            projectId: watchConfig.projectId,
            checksum: checksum,
            sourcePath: sourceURL.path,
            sourceSize: fileSize,
            sourceFormat: detectFormat(pathExtension: sourceURL.pathExtension.lowercased()),
            sourceFps: 24.0,
            sourceTimecodeStart: readTimecodeSidecar(for: sourceURL) ?? "00:00:00:00",
            duration: 0,
            proxyPath: nil,
            proxyStatus: .pending,
            proxyChecksum: nil,
            narrativeMeta: watchConfig.mode == .narrative ? .init(
                sceneNumber: sourceURL.deletingPathExtension().lastPathComponent,
                shotCode: "A",
                takeNumber: 1,
                cameraId: "A"
            ) : nil,
            documentaryMeta: watchConfig.mode == .documentary ? .init(
                subjectName: sourceURL.deletingPathExtension().lastPathComponent,
                subjectId: UUID().uuidString,
                shootingDay: 1,
                sessionLabel: "Ingest"
            ) : nil,
            audioTracks: [],
            syncResult: .unsynced,
            syncedAudioPath: nil,
            aiScores: nil,
            transcriptId: nil,
            aiProcessingStatus: .pending,
            reviewStatus: .unreviewed,
            annotations: [],
            approvalStatus: .pending,
            approvedBy: nil,
            approvedAt: nil,
            ingestedAt: timestamp,
            updatedAt: timestamp,
            projectMode: watchConfig.mode
        )
    }

    private func detectFormat(pathExtension: String) -> SourceFormat {
        switch pathExtension {
        case "braw":
            return .braw
        case "ari", "arx":
            return .arriraw
        case "mov":
            return .proRes422HQ
        case "mxf":
            return .mxf
        case "r3d":
            return .r3d
        default:
            return .h264
        }
    }

    private func readTimecodeSidecar(for url: URL) -> String? {
        let sidecarURL = url.deletingPathExtension().appendingPathExtension("timecode.json")
        guard let data = try? Data(contentsOf: sidecarURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return nil
        }
        return payload["timecode"]
    }

    private func findExternalAudioFiles(near videoURL: URL) -> [URL] {
        guard let siblings = try? FileManager.default.contentsOfDirectory(
            at: videoURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return siblings
            .filter { $0 != videoURL }
            .filter { supportedAudioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func sourceFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? Int64) ?? 0
    }

    private func report(filename: String, progress: Double, stage: IngestStage) {
        onProgress(.init(filename: filename, progress: progress, stage: stage))
    }
}

public actor IngestDaemon {
    private let store: GRDBStore
    private var watchFolders: [String: WatchFolderConfig] = [:]
    private var progressReport = IngestProgressReport()

    public init(dbPath: String? = nil) throws {
        if let dbPath {
            self.store = try GRDBStore(path: dbPath)
        } else {
            self.store = .shared
        }
    }

    public func addWatchFolder(_ config: WatchFolderConfig) async throws {
        watchFolders[config.path] = config
        try await store.saveWatchFolder(config)
    }

    public func allWatchFolders() async throws -> [WatchFolderConfig] {
        try await store.allWatchFolders()
    }

    public func ingestFile(at sourceURL: URL) async throws -> Clip {
        guard let config = watchFolders.values.first(where: { sourceURL.path.hasPrefix($0.path) }) else {
            throw IngestDaemonError.noWatchFolder(path: sourceURL.path)
        }

        let pipeline = IngestPipeline(watchConfig: config, store: store) { [weak self] item in
            Task {
                await self?.updateProgress(with: item)
            }
        }

        return try await pipeline.ingest(sourceURL: sourceURL)
    }

    public func currentProgress() -> IngestProgressReport {
        progressReport
    }

    public func stop() {
    }
    
    public func resumeInterruptedIngests() async {
        let stuckThreshold: TimeInterval = 300  // 5 minutes
        let now = Date().timeIntervalSince1970
        let stuckStages: [GRDBStore.IngestStage] = [.copying, .checksumming, .proxyActive]

        let stuck = try? await store.fetchStuckIngestQueue(olderThan: now - stuckThreshold)

        for item in stuck ?? [] {
            print("[IngestDaemon] Resuming interrupted item: \(URL(fileURLWithPath: item.sourcePath).lastPathComponent) (was: \(item.stage.rawValue))")
            let resetStage = (item.stage == .proxyActive) ? GRDBStore.IngestStage.proxyPending : GRDBStore.IngestStage.queued
            try? await store.updateIngestQueueStage(id: item.id, stage: resetStage, error: nil)
            
            // Re-enqueue for processing
            Task {
                do {
                    let sourceURL = URL(fileURLWithPath: item.sourcePath)
                    _ = try await ingestFile(at: sourceURL)
                } catch {
                    print("[IngestDaemon] Failed to resume \(item.sourcePath): \(error)")
                }
            }
        }
    }

    private func updateProgress(with item: IngestProgressItem) {
        progressReport.active.removeAll { $0.filename == item.filename }
        if item.stage != .complete && item.stage != .error {
            progressReport.active.append(item)
        }
        if item.stage == .error, let message = item.error {
            progressReport.errors.append(
                IngestError(filename: item.filename, message: message)
            )
        }

        NotificationCenter.default.post(
            name: Notification.Name("ingestProgressUpdated"),
            object: progressReport
        )
    }
}

enum ChecksumUtil {
    static func sha256(fileURL: URL) throws -> String {
        guard let stream = InputStream(url: fileURL) else {
            throw CocoaError(.fileReadUnknown)
        }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let chunkSize = 1_048_576
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                throw stream.streamError ?? CocoaError(.fileReadUnknown)
            }
            if bytesRead == 0 {
                break
            }
            hasher.update(data: Data(buffer.prefix(bytesRead)))
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
