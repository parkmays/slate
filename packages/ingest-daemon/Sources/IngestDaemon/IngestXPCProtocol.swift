import Foundation

// MARK: - App ← Daemon (progress push)

@objc public protocol IngestClientXPCProtocol {
    func progressDidUpdate(_ report: IngestProgressReportXPC, withReply reply: @escaping () -> Void)
}

// MARK: - App → Daemon (control)

@objc public protocol IngestDaemonXPCProtocol {
    func registerWatchFolder(_ config: WatchFolderConfigXPC, withReply reply: @escaping (Bool) -> Void)
    func pauseIngest(withReply reply: @escaping () -> Void)
    func resumeIngest(withReply reply: @escaping () -> Void)
    func cancelClip(_ clipId: String, withReply reply: @escaping () -> Void)
}

// XPC requires @objc-compatible value types (NSSecureCoding):
@objcMembers
public final class IngestProgressReportXPC: NSObject, NSSecureCoding {
    public var activeItemCount: Int = 0
    public var totalProcessed: Int = 0
    public var totalQueued: Int = 0
    public var currentClipId: String = ""
    public var currentStage: String = ""   // matches IngestStage raw strings from shared types
    public var progressPercent: Double = 0.0
    public var errorMessage: String = ""

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(activeItemCount, forKey: "activeItemCount")
        coder.encode(totalProcessed, forKey: "totalProcessed")
        coder.encode(totalQueued, forKey: "totalQueued")
        coder.encode(currentClipId, forKey: "currentClipId")
        coder.encode(currentStage, forKey: "currentStage")
        coder.encode(progressPercent, forKey: "progressPercent")
        coder.encode(errorMessage, forKey: "errorMessage")
    }

    public required init?(coder: NSCoder) {
        activeItemCount = coder.decodeInteger(forKey: "activeItemCount")
        totalProcessed = coder.decodeInteger(forKey: "totalProcessed")
        totalQueued = coder.decodeInteger(forKey: "totalQueued")
        currentClipId = coder.decodeObject(of: NSString.self, forKey: "currentClipId") as String? ?? ""
        currentStage = coder.decodeObject(of: NSString.self, forKey: "currentStage") as String? ?? ""
        progressPercent = coder.decodeDouble(forKey: "progressPercent")
        errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String? ?? ""
        super.init()
    }

    public override init() { super.init() }
}

/// NSObject XPC payloads are not formally `Sendable`; unchecked is appropriate for IPC handoff.
extension IngestProgressReportXPC: @unchecked Sendable {}

@objcMembers
public final class WatchFolderConfigXPC: NSObject, NSSecureCoding {
    public var id: String = ""
    public var path: String = ""
    public var projectId: String = ""
    public var mode: String = ""   // "narrative" | "documentary"

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(path, forKey: "path")
        coder.encode(projectId, forKey: "projectId")
        coder.encode(mode, forKey: "mode")
    }

    public required init?(coder: NSCoder) {
        id = coder.decodeObject(of: NSString.self, forKey: "id") as String? ?? ""
        path = coder.decodeObject(of: NSString.self, forKey: "path") as String? ?? ""
        projectId = coder.decodeObject(of: NSString.self, forKey: "projectId") as String? ?? ""
        mode = coder.decodeObject(of: NSString.self, forKey: "mode") as String? ?? "narrative"
        super.init()
    }

    public override init() { super.init() }
}
