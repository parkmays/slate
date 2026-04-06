import Foundation
import SLATESharedTypes

// MARK: - XPC reply boxing (Swift 6: NSXPC reply handlers are not `Sendable`)

private struct XPCBoolReply: @unchecked Sendable {
    let reply: (Bool) -> Void
    init(_ reply: @escaping (Bool) -> Void) { self.reply = reply }
}

private struct XPCVoidReply: @unchecked Sendable {
    let reply: () -> Void
    init(_ reply: @escaping () -> Void) { self.reply = reply }
}

/// Pushes ingest progress to the desktop app over XPC (daemon → client).
public enum IngestXPCProgressDispatcher {
    private static let lock = NSLock()
    private static nonisolated(unsafe) weak var clientProxy: IngestClientXPCProtocol?

    public static func setClientProxy(_ proxy: IngestClientXPCProtocol?) {
        lock.lock()
        clientProxy = proxy
        lock.unlock()
    }

    public static func pushProgressReport(_ report: IngestProgressReport) {
        let xpc = IngestProgressReportXPC()
        xpc.activeItemCount = report.active.count
        xpc.totalProcessed = 0
        xpc.totalQueued = report.queued
        if let first = report.active.first {
            xpc.currentClipId = first.filename
            xpc.currentStage = first.stage.rawValue
            xpc.progressPercent = first.progress * 100.0
            xpc.errorMessage = first.error ?? ""
        }
        if let lastError = report.errors.last {
            xpc.errorMessage = lastError.message
        }

        lock.lock()
        let proxy = clientProxy
        lock.unlock()

        guard let proxy else { return }
        proxy.progressDidUpdate(xpc) {}
    }
}

// MARK: - Daemon endpoint (app calls into ingest)

@objc
final class IngestXPCDaemonEndpoint: NSObject, IngestDaemonXPCProtocol {
    private let daemon: IngestDaemon

    init(daemon: IngestDaemon) {
        self.daemon = daemon
        super.init()
    }

    func registerWatchFolder(_ config: WatchFolderConfigXPC, withReply reply: @escaping (Bool) -> Void) {
        let path = config.path
        let projectId = config.projectId
        let modeRaw = config.mode
        let boxed = XPCBoolReply(reply)
        Task { [daemon] in
            do {
                let mode = ProjectMode(rawValue: modeRaw) ?? .narrative
                let wf = WatchFolder(path: path, projectId: projectId, mode: mode)
                try await daemon.addWatchFolder(wf)
                boxed.reply(true)
            } catch {
                boxed.reply(false)
            }
        }
    }

    func pauseIngest(withReply reply: @escaping () -> Void) {
        let boxed = XPCVoidReply(reply)
        Task { [daemon] in
            await daemon.pauseIngest()
            boxed.reply()
        }
    }

    func resumeIngest(withReply reply: @escaping () -> Void) {
        let boxed = XPCVoidReply(reply)
        Task { [daemon] in
            await daemon.resumeIngestFromPause()
            boxed.reply()
        }
    }

    func cancelClip(_ clipId: String, withReply reply: @escaping () -> Void) {
        let boxed = XPCVoidReply(reply)
        Task { [daemon] in
            await daemon.cancelClip(clipId: clipId)
            boxed.reply()
        }
    }
}

// MARK: - Listener

public final class IngestXPCListener: NSObject, NSXPCListenerDelegate {
    public static let serviceName = "com.mountaintoppics.slate.ingestd"

    private let listener: NSXPCListener
    private let daemon: IngestDaemon

    public init(daemon: IngestDaemon) {
        self.daemon = daemon
        self.listener = NSXPCListener(machServiceName: Self.serviceName)
        super.init()
        listener.delegate = self
    }

    public func start() {
        listener.resume()
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: IngestDaemonXPCProtocol.self)
        newConnection.remoteObjectInterface = NSXPCInterface(with: IngestClientXPCProtocol.self)
        newConnection.exportedObject = IngestXPCDaemonEndpoint(daemon: daemon)

        newConnection.invalidationHandler = {
            IngestXPCProgressDispatcher.setClientProxy(nil)
        }

        newConnection.interruptionHandler = {
            IngestXPCProgressDispatcher.setClientProxy(nil)
        }

        newConnection.resume()

        let proxy = newConnection.remoteObjectProxyWithErrorHandler { _ in
            IngestXPCProgressDispatcher.setClientProxy(nil)
        }
        if let client = proxy as? IngestClientXPCProtocol {
            IngestXPCProgressDispatcher.setClientProxy(client)
        }

        return true
    }
}
