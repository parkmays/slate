import Foundation

/// SLATE engine / app version metadata (see repo `VERSION` for release process).
public enum SLATEVersion {
    public static let major = 1
    public static let minor = 2
    public static let patch = 0
    public static let prerelease: String? = nil
    public static let build: String? = nil

    public static var string: String {
        let pre = prerelease.map { "-\($0)" } ?? ""
        let b = build.map { "+\($0)" } ?? ""
        return "\(major).\(minor).\(patch)\(pre)\(b)"
    }

    public static var fullString: String { "SLATE AI/ML Engine v\(string)" }

    public static let date = "2026-04-03"
    public static let copyright = "Copyright © 2026 SLATE. All rights reserved."

    /// Compares dotted numeric version strings (e.g. `1.2.0` vs `1.10.0`).
    public static func compareVersionStrings(_ left: String, _ right: String) -> ComparisonResult {
        let leftComponents = left.split(separator: ".").compactMap { Int($0) }
        let rightComponents = right.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(leftComponents.count, rightComponents.count)
        for i in 0..<maxCount {
            let lv = i < leftComponents.count ? leftComponents[i] : 0
            let rv = i < rightComponents.count ? rightComponents[i] : 0
            if lv < rv { return .orderedAscending }
            if lv > rv { return .orderedDescending }
        }
        return .orderedSame
    }
}

// MARK: - Build configuration

#if DEBUG
public let SLATE_BUILD_CONFIGURATION = "Debug"
#else
public let SLATE_BUILD_CONFIGURATION = "Release"
#endif

#if arch(arm64)
public let SLATE_ARCHITECTURE = "arm64"
#elseif arch(x86_64)
public let SLATE_ARCHITECTURE = "x86_64"
#else
public let SLATE_ARCHITECTURE = "unknown"
#endif
