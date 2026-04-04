import Foundation
import SLATESharedTypes

@MainActor
class IPCManager: NSObject, ObservableObject, IngestXPCProtocol {
    static let shared = IPCManager()
    private var connection: NSXPCConnection?
    @Published var progressReport: IngestProgressReportXPC = .init()
    @Published var isConnected: Bool = false

    func connect() {
        let conn = NSXPCConnection(serviceName: "com.mountaintoppics.slate.ingestd")
        conn.remoteObjectInterface = NSXPCInterface(with: IngestXPCProtocol.self)
        conn.exportedObject = self
        conn.exportedInterface = NSXPCInterface(with: IngestXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.isConnected = false }
        }
        conn.resume()
        connection = conn
        isConnected = true
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
        isConnected = false
    }

    // MARK: - IngestXPCProtocol (daemon → app direction)

    // Called by daemon when progress updates:
    nonisolated func progressDidUpdate(_ report: IngestProgressReportXPC, withReply reply: @escaping () -> Void) {
        Task { @MainActor in
            self.progressReport = report
        }
        reply()
    }

    // Stub implementations — the daemon never calls these on the app object.
    // The app calls them on the daemon via remoteObjectProxy (see helpers below).
    nonisolated func registerWatchFolder(_ config: WatchFolderConfigXPC, withReply reply: @escaping (Bool) -> Void) {
        reply(false)
    }
    nonisolated func pauseIngest(withReply reply: @escaping () -> Void) { reply() }
    nonisolated func resumeIngest(withReply reply: @escaping () -> Void) { reply() }
    nonisolated func cancelClip(_ clipId: String, withReply reply: @escaping () -> Void) { reply() }

    // MARK: - App → Daemon helpers

    func sendRegisterWatchFolder(_ config: WatchFolderConfig) async -> Bool {
        guard let proxy = connection?.remoteObjectProxy as? IngestXPCProtocol else { return false }
        return await withCheckedContinuation { cont in
            proxy.registerWatchFolder(config.toXPC()) { success in cont.resume(returning: success) }
        }
    }

    func sendPauseIngest() {
        (connection?.remoteObjectProxy as? IngestXPCProtocol)?.pauseIngest { }
    }

    func sendResumeIngest() {
        (connection?.remoteObjectProxy as? IngestXPCProtocol)?.resumeIngest { }
    }

    func sendCancelClip(_ clipId: String) {
        (connection?.remoteObjectProxy as? IngestXPCProtocol)?.cancelClip(clipId) { }
    }

    // MARK: - Derived display model (XPC type → SwiftUI-friendly type)

    /// Maps the compact XPC progress report into the full IngestProgressReport
    /// the rest of the UI already knows how to render.
    var displayReport: IngestProgressReport {
        guard !progressReport.currentClipId.isEmpty else {
            return IngestProgressReport()
        }
        let stage: IngestStage
        switch progressReport.currentStage {
        case "copying":        stage = .copy
        case "checksumming":   stage = .checksum
        case "proxy_pending",
             "proxy_active",
             "proxy":          stage = .proxy
        case "sync_pending",
             "sync":           stage = .sync
        case "complete":       stage = .complete
        default:               stage = .checksum
        }
        let filename = URL(fileURLWithPath: progressReport.currentClipId).lastPathComponent
        let item = IngestProgressItem(
            filename: filename.isEmpty ? progressReport.currentClipId : filename,
            progress: progressReport.progressPercent / 100.0,
            stage: stage,
            error: progressReport.errorMessage.isEmpty ? nil : progressReport.errorMessage
        )
        let errors: [IngestError] = progressReport.errorMessage.isEmpty ? [] :
            [IngestError(filename: filename, message: progressReport.errorMessage)]
        return IngestProgressReport(
            active: [item],
            queued: progressReport.totalQueued,
            errors: errors
        )
    }
}

// Extension to convert between app types and XPC types
extension WatchFolderConfig {
    func toXPC() -> WatchFolderConfigXPC {
        let xpc = WatchFolderConfigXPC()
        xpc.id = self.path          // WatchFolder uses path as its identifier
        xpc.path = self.path
        xpc.projectId = self.projectId
        xpc.mode = self.mode.rawValue
        return xpc
    }
}

extension WatchFolderConfigXPC {
    func fromXPC() -> WatchFolderConfig {
        return WatchFolderConfig(
            path: self.path,
            projectId: self.projectId,
            mode: ProjectMode(rawValue: self.mode) ?? .narrative
        )
    }
}
