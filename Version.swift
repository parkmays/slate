/// SLATE Version Information
public struct SLATEVersion {
    public static let major = 1
    public static let minor = 2
    public static let patch = 0
    public static let prerelease: String? = nil
    public static let build: String? = nil
    
    public static let string = "\(major).\(minor).\(patch)\(
        prerelease.map { "-\($0)" } ?? ""
    )\(
        build.map { "+\($0)" } ?? ""
    )"
    
    public static let fullString = "SLATE AI/ML Engine v\(string)"
    
    public static let date = "2026-04-03"
    public static let copyright = "Copyright © 2026 SLATE. All rights reserved."
}

// MARK: - Build Configuration

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

// MARK: - Version Comparison

extension SLATEVersion {
    public static func >=(_ left: String, _ right: String) -> Bool {
        return compare(left, right) != .orderedAscending
    }
    
    public static func <=(_ left: String, _ right: String) -> Bool {
        return compare(left, right) != .orderedDescending
    }
    
    public static func >(_ left: String, _ right: String) -> Bool {
        return compare(left, right) == .orderedDescending
    }
    
    public static func <(_ left: String, _ right: String) -> Bool {
        return compare(left, right) == .orderedAscending
    }
    
    private static func compare(_ left: String, _ right: String) -> ComparisonResult {
        let leftComponents = left.components(separatedBy: ".").compactMap { Int($0) }
        let rightComponents = right.components(separatedBy: ".").compactMap { Int($0) }
        
        let maxCount = max(leftComponents.count, rightComponents.count)
        
        for i in 0..<maxCount {
            let leftValue = i < leftComponents.count ? leftComponents[i] : 0
            let rightValue = i < rightComponents.count ? rightComponents[i] : 0
            
            if leftValue < rightValue {
                return .orderedAscending
            } else if leftValue > rightValue {
                return .orderedDescending
            }
        }
        
        return .orderedSame
    }
}
