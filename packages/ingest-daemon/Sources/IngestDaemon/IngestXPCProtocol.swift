import Foundation

@objc protocol IngestXPCProtocol {
    // Daemon → App: push progress
    func progressDidUpdate(_ report: IngestProgressReportXPC, withReply reply: @escaping () -> Void)

    // App → Daemon: control
    func registerWatchFolder(_ config: WatchFolderConfigXPC, withReply reply: @escaping (Bool) -> Void)
    func pauseIngest(withReply reply: @escaping () -> Void)
    func resumeIngest(withReply reply: @escaping () -> Void)
    func cancelClip(_ clipId: String, withReply reply: @escaping () -> Void)
}

// XPC requires @objc-compatible value types (NSSecureCoding):
@objcMembers
final class IngestProgressReportXPC: NSObject, NSSecureCoding {
    var activeItemCount: Int = 0
    var totalProcessed: Int = 0
    var totalQueued: Int = 0
    var currentClipId: String = ""
    var currentStage: String = ""   // "copying" | "checksumming" | "proxy" | "sync"
    var progressPercent: Double = 0.0
    var errorMessage: String = ""

    static var supportsSecureCoding: Bool { true }

    func encode(with coder: NSCoder) {
        coder.encode(activeItemCount, forKey: "activeItemCount")
        coder.encode(totalProcessed, forKey: "totalProcessed")
        coder.encode(totalQueued, forKey: "totalQueued")
        coder.encode(currentClipId, forKey: "currentClipId")
        coder.encode(currentStage, forKey: "currentStage")
        coder.encode(progressPercent, forKey: "progressPercent")
        coder.encode(errorMessage, forKey: "errorMessage")
    }

    required init?(coder: NSCoder) {
        activeItemCount = coder.decodeInteger(forKey: "activeItemCount")
        totalProcessed = coder.decodeInteger(forKey: "totalProcessed")
        totalQueued = coder.decodeInteger(forKey: "totalQueued")
        currentClipId = coder.decodeObject(of: NSString.self, forKey: "currentClipId") as String? ?? ""
        currentStage = coder.decodeObject(of: NSString.self, forKey: "currentStage") as String? ?? ""
        progressPercent = coder.decodeDouble(forKey: "progressPercent")
        errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage") as String? ?? ""
    }

    override init() { super.init() }
}

@objcMembers
final class WatchFolderConfigXPC: NSObject, NSSecureCoding {
    var id: String = ""
    var path: String = ""
    var projectId: String = ""
    var mode: String = ""   // "narrative" | "documentary"

    static var supportsSecureCoding: Bool { true }

    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(path, forKey: "path")
        coder.encode(projectId, forKey: "projectId")
        coder.encode(mode, forKey: "mode")
    }

    required init?(coder: NSCoder) {
        id = coder.decodeObject(of: NSString.self, forKey: "id") as String? ?? ""
        path = coder.decodeObject(of: NSString.self, forKey: "path") as String? ?? ""
        projectId = coder.decodeObject(of: NSString.self, forKey: "projectId") as String? ?? ""
        mode = coder.decodeObject(of: NSString.self, forKey: "mode") as String? ?? "narrative"
    }

    override init() { super.init() }
}
