import Foundation
import IngestDaemon
import SLATESharedTypes

/// Receives ingest progress from `slate-ingest` over XPC and exposes `IngestProgressReport` for SwiftUI.
@MainActor
public final class IPCManager: NSObject, ObservableObject, IngestClientXPCProtocol {
    public static let shared = IPCManager()

    private override init() {
        super.init()
    }

    private var connection: NSXPCConnection?
    @Published public private(set) var progressReport: IngestProgressReportXPC = .init()
    @Published public private(set) var isConnected: Bool = false

    public func connect() {
        disconnect()
        let conn = NSXPCConnection(machServiceName: IngestXPCListener.serviceName, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: IngestDaemonXPCProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: IngestClientXPCProtocol.self)
        conn.exportedObject = self
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        conn.resume()
        connection = conn
        isConnected = true
    }

    public func disconnect() {
        connection?.invalidate()
        connection = nil
        isConnected = false
    }

    // MARK: - IngestClientXPCProtocol (daemon → app)

    nonisolated public func progressDidUpdate(_ report: IngestProgressReportXPC, withReply reply: @escaping () -> Void) {
        Task { @MainActor in
            self.progressReport = report
        }
        reply()
    }

    // MARK: - App → daemon

    func sendRegisterWatchFolder(_ config: WatchFolder) async -> Bool {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? IngestDaemonXPCProtocol else {
            return false
        }
        return await withCheckedContinuation { cont in
            proxy.registerWatchFolder(config.toXPC()) { success in
                cont.resume(returning: success)
            }
        }
    }

    func sendPauseIngest() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? IngestDaemonXPCProtocol else {
            return
        }
        proxy.pauseIngest { }
    }

    func sendResumeIngest() {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? IngestDaemonXPCProtocol else {
            return
        }
        proxy.resumeIngest { }
    }

    func sendCancelClip(_ clipId: String) {
        guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in }) as? IngestDaemonXPCProtocol else {
            return
        }
        proxy.cancelClip(clipId) { }
    }

    // MARK: - Derived display model (XPC → shared IngestProgressReport)

    public var displayReport: IngestProgressReport {
        guard !progressReport.currentClipId.isEmpty else {
            return IngestProgressReport()
        }
        let stage: IngestStage
        switch progressReport.currentStage {
        case "copy", "copying":
            stage = .copy
        case "checksum", "checksumming":
            stage = .checksum
        case "proxy_pending", "proxy_active", "proxy":
            stage = .proxy
        case "sync_pending", "sync":
            stage = .sync
        case "complete":
            stage = .complete
        case "error":
            stage = .error
        default:
            stage = .checksum
        }
        let filename = progressReport.currentClipId
        let item = IngestProgressItem(
            filename: filename,
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

extension WatchFolder {
    func toXPC() -> WatchFolderConfigXPC {
        let xpc = WatchFolderConfigXPC()
        xpc.id = path
        xpc.path = path
        xpc.projectId = projectId
        xpc.mode = mode.rawValue
        return xpc
    }
}
