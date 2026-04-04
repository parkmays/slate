import Foundation
import IngestDaemon
import SLATESharedTypes

@main
struct IngestDaemonCLI {
    static func main() async throws {
        let options = CLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))
        let daemon = try IngestDaemon(dbPath: options.dbPath)

        if let watchFolder = options.watchFolder,
           let projectId = options.projectId,
           let mode = options.mode {
            try await daemon.addWatchFolder(
                WatchFolderConfig(path: watchFolder, projectId: projectId, mode: mode)
            )
            print("Watching \(watchFolder) for project \(projectId)")
        } else {
            print("SLATE ingest daemon initialized without a watch folder.")
        }

        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}

private struct CLIOptions {
    var dbPath: String?
    var watchFolder: String?
    var projectId: String?
    var mode: ProjectMode?

    init(arguments: [String]) {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--db-path":
                dbPath = Self.value(after: &index, in: arguments)
            case "--watch-folder":
                watchFolder = Self.value(after: &index, in: arguments)
            case "--project-id":
                projectId = Self.value(after: &index, in: arguments)
            case "--mode":
                if let rawValue = Self.value(after: &index, in: arguments) {
                    mode = ProjectMode(rawValue: rawValue)
                }
            default:
                break
            }
            index += 1
        }
    }

    private static func value(after index: inout Int, in arguments: [String]) -> String? {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            return nil
        }
        index = nextIndex
        return arguments[nextIndex]
    }
}
