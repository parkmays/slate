import Foundation

/// Runtime configuration for the iOS app.
///
/// API shapes and versioning live in the monorepo root `contracts/` directory (e.g. `web-api.json`).
/// Set `SUPABASE_URL` / `SUPABASE_ANON_KEY` in Xcode scheme environment or Info.plist for local dev.
enum SLATEMobileConfig {
    /// Canonical contracts path relative to the **repository root** (not bundled in the app by default).
    static let contractsWebAPIFilename = "web-api.json"

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
