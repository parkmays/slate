// SLATE — WatchFolderDaemon
// Owned by: Claude Code
//
// FSEvents-based daemon that monitors registered watch folders and triggers
// the ingest pipeline whenever new camera files appear.
//
// RULES:
//   - Never touch source files — READ ONLY
//   - File stability check: poll size twice (2s apart) before ingesting
//   - Duplicate detection: skip files already in GRDB by checksum

import Foundation
import CoreServices
import SLATESharedTypes

// MARK: - WatchFolderDaemon

public actor WatchFolderDaemon {

    // MARK: - State

    private var watchConfigs: [String: WatchFolderConfig] = [:]   // path → config
    private var eventStream: FSEventStreamRef?
    private var pendingFiles: [String: Date] = [:]                // path → first seen
    private var ingestingFiles: Set<String> = []
    private var progressReport: IngestProgressReport = .init()

    // MARK: - Callbacks

    private let onProgress: @Sendable (IngestProgressReport) -> Void
    private let onClipIngested: @Sendable (Clip) -> Void
    private let onError: @Sendable (String, Error) -> Void

    // MARK: - Init

    public init(
        onProgress: @escaping @Sendable (IngestProgressReport) -> Void,
        onClipIngested: @escaping @Sendable (Clip) -> Void,
        onError: @escaping @Sendable (String, Error) -> Void
    ) {
        self.onProgress = onProgress
        self.onClipIngested = onClipIngested
        self.onError = onError
    }

    // MARK: - Register / unregister

    public func register(config: WatchFolderConfig) {
        watchConfigs[config.path] = config
        restartStream()
    }

    public func unregister(path: String) {
        watchConfigs.removeValue(forKey: path)
        restartStream()
    }

    public func registeredFolders() -> [WatchFolderConfig] {
        Array(watchConfigs.values)
    }

    // MARK: - Progress access

    public func currentReport() -> IngestProgressReport {
        progressReport
    }

    // MARK: - FSEvents stream management

    private func restartStream() {
        stopStream()
        guard !watchConfigs.isEmpty else { return }
        startStream(paths: Array(watchConfigs.keys))
    }

    private func startStream(paths: [String]) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self as AnyObject).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let cfPaths = paths as CFArray
        let latency: CFTimeInterval = 1.0  // coalesce events within 1 second

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fsEventCallback,
            &context,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents |
                                      kFSEventStreamCreateFlagUseCFTypes |
                                      kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        self.eventStream = stream
    }

    private func stopStream() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.eventStream = nil
    }

    // MARK: - Event handling (called from C callback)

    nonisolated func handleEvents(paths: [String], flags: [UInt32]) {
        Task { await self.processEvents(paths: paths, flags: flags) }
    }

    private func processEvents(paths: [String], flags: [UInt32]) async {
        let supportedExtensions: Set<String> = ["ari", "arx", "braw", "mov", "mxf", "mp4", "r3d"]

        for (path, flag) in zip(paths, flags) {
            // Only care about file created / renamed-to events
            let isCreated  = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated))  != 0
            let isModified = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)) != 0
            let isFile     = (flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile))   != 0

            guard isFile && (isCreated || isModified) else { continue }

            let ext = (path as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            guard !ingestingFiles.contains(path) else { continue }

            // Find which watch config owns this path
            guard let config = watchConfig(for: path) else { continue }

            // Record first-seen timestamp for stability check
            if pendingFiles[path] == nil {
                pendingFiles[path] = Date()
            }

            // Schedule stability check after 2 seconds
            let capturedPath = path
            let capturedConfig = config
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self.stabilityCheckAndIngest(path: capturedPath, config: capturedConfig)
            }
        }
    }

    private func stabilityCheckAndIngest(path: String, config: WatchFolderConfig) async {
        guard !ingestingFiles.contains(path) else { return }

        // File stability: compare size before and after 2 seconds
        let size1 = fileSize(at: path)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let size2 = fileSize(at: path)

        guard size1 > 0, size1 == size2 else {
            // File still growing — re-queue
            let capturedPath = path
            let capturedConfig = config
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self.stabilityCheckAndIngest(path: capturedPath, config: capturedConfig)
            }
            return
        }

        pendingFiles.removeValue(forKey: path)
        ingestingFiles.insert(path)
        progressReport.queued = max(0, progressReport.queued - 1)

        let sourceURL = URL(fileURLWithPath: path)
        let pipeline = IngestPipeline(watchConfig: config) { [weak self] item in
            Task { await self?.updateProgress(item: item) }
        }

        do {
            let clip = try await pipeline.ingest(sourceURL: sourceURL)
            ingestingFiles.remove(path)
            onClipIngested(clip)
        } catch {
            ingestingFiles.remove(path)
            let filename = sourceURL.lastPathComponent
            progressReport.errors.append(
                SLATESharedTypes.IngestError(filename: filename, message: error.localizedDescription)
            )
            onError(path, error)
        }

        publishProgress()
    }

    // MARK: - Helpers

    private func watchConfig(for filePath: String) -> WatchFolderConfig? {
        for (watchPath, config) in watchConfigs {
            if filePath.hasPrefix(watchPath) { return config }
        }
        return nil
    }

    private func fileSize(at path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    private func updateProgress(item: IngestProgressItem) {
        if item.stage == .complete || item.stage == .error {
            progressReport.active.removeAll { $0.filename == item.filename }
        } else {
            if let idx = progressReport.active.firstIndex(where: { $0.filename == item.filename }) {
                progressReport.active[idx] = item
            } else {
                progressReport.active.append(item)
            }
        }
        publishProgress()
    }

    private func publishProgress() {
        let report = progressReport
        onProgress(report)
    }
}

// MARK: - C-level FSEvents callback

private func fsEventCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let daemon = Unmanaged<AnyObject>.fromOpaque(info).takeUnretainedValue() as! WatchFolderDaemon

    guard let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
    let flags = (0..<numEvents).map { eventFlags[$0] }

    daemon.handleEvents(paths: cfPaths, flags: flags)
}
