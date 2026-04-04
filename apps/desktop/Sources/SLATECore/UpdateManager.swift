import Foundation
import SwiftUI

public struct DesktopAppRelease: Codable, Identifiable, Sendable, Equatable {
    public var version: String
    public var build: String
    public var minimumOSVersion: String?
    public var downloadURL: String
    public var releaseNotesURL: String?
    public var publishedAt: String?
    public var sha256: String?

    public var id: String {
        "\(version)-\(build)"
    }

    public init(
        version: String,
        build: String,
        minimumOSVersion: String? = nil,
        downloadURL: String,
        releaseNotesURL: String? = nil,
        publishedAt: String? = nil,
        sha256: String? = nil
    ) {
        self.version = version
        self.build = build
        self.minimumOSVersion = minimumOSVersion
        self.downloadURL = downloadURL
        self.releaseNotesURL = releaseNotesURL
        self.publishedAt = publishedAt
        self.sha256 = sha256
    }
}

private struct DesktopAppcastEnvelope: Decodable {
    let releases: [DesktopAppRelease]
}

@MainActor
public final class UpdateManager: ObservableObject {
    @Published public private(set) var checking = false
    @Published public private(set) var latestRelease: DesktopAppRelease?
    @Published public var errorMessage: String?

    private let bundle: Bundle
    private let session: URLSession

    public init(bundle: Bundle = .main, session: URLSession = .shared) {
        self.bundle = bundle
        self.session = session
    }

    public var currentVersion: String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    public var currentBuild: String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    public var configuredFeedURL: URL? {
        if let envValue = ProcessInfo.processInfo.environment["SLATE_DESKTOP_UPDATE_FEED_URL"],
           let url = URL(string: envValue),
           !envValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url
        }

        if let bundleValue = bundle.object(forInfoDictionaryKey: "SLATEUpdateFeedURL") as? String,
           let url = URL(string: bundleValue),
           !bundleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return url
        }

        return nil
    }

    public var updateAvailable: Bool {
        guard let latestRelease else {
            return false
        }
        return latestRelease.isNewer(thanVersion: currentVersion, build: currentBuild)
    }

    public func checkForUpdates() async {
        guard let feedURL = configuredFeedURL else {
            errorMessage = "Set SLATE_DESKTOP_UPDATE_FEED_URL or SLATEUpdateFeedURL to enable release checks."
            latestRelease = nil
            return
        }

        checking = true
        errorMessage = nil
        defer { checking = false }

        do {
            let (data, response) = try await session.data(from: feedURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateManagerError.invalidResponse
            }

            let envelope = try JSONDecoder().decode(DesktopAppcastEnvelope.self, from: data)
            latestRelease = envelope.releases.sorted(by: releaseSortPredicate).first
        } catch {
            latestRelease = nil
            errorMessage = error.localizedDescription
        }
    }

    private func releaseSortPredicate(_ lhs: DesktopAppRelease, _ rhs: DesktopAppRelease) -> Bool {
        if lhs.version != rhs.version {
            return compareVersions(lhs.version, rhs.version) == .orderedDescending
        }
        return compareBuilds(lhs.build, rhs.build) == .orderedDescending
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<count {
            let left = index < lhsComponents.count ? lhsComponents[index] : 0
            let right = index < rhsComponents.count ? rhsComponents[index] : 0

            if left != right {
                return left < right ? .orderedAscending : .orderedDescending
            }
        }

        return .orderedSame
    }

    private func compareBuilds(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = Int(lhs) ?? 0
        let right = Int(rhs) ?? 0
        if left == right {
            return .orderedSame
        }
        return left < right ? .orderedAscending : .orderedDescending
    }
}

private enum UpdateManagerError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The update feed did not return a valid release response."
        }
    }
}

private extension DesktopAppRelease {
    func isNewer(thanVersion currentVersion: String, build currentBuild: String) -> Bool {
        let currentVersionComponents = currentVersion.split(separator: ".").map { Int($0) ?? 0 }
        let releaseVersionComponents = version.split(separator: ".").map { Int($0) ?? 0 }
        let versionCount = max(currentVersionComponents.count, releaseVersionComponents.count)

        for index in 0..<versionCount {
            let current = index < currentVersionComponents.count ? currentVersionComponents[index] : 0
            let release = index < releaseVersionComponents.count ? releaseVersionComponents[index] : 0
            if current != release {
                return release > current
            }
        }

        return (Int(build) ?? 0) > (Int(currentBuild) ?? 0)
    }
}
