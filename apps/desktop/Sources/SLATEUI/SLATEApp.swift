// SLATE — SLATEApp
// Owned by: Claude Code
//
// C4: Wires Supabase Auth + Realtime into the app lifecycle.
//   • SupabaseManager is created here and passed as @EnvironmentObject to all
//     descendants (so ShareLinkSheet and ProxyPlayerView get the real JWT).
//   • Auth gate: shows AuthView until the user is signed in (or skips to
//     ContentView immediately when Supabase is not configured / user hits
//     "Continue Offline").
//   • setupApp() starts the auth state listener and wires the ingest daemon.

import AppKit
import IngestDaemon
import SwiftUI
import SLATECore
import SLATESharedTypes

public struct SLATEApp: App {

    @StateObject private var appState        = AppState()
    @StateObject private var supabaseManager = SupabaseManager()

    /// True when the user has explicitly chosen to continue without signing in.
    @State private var offlineOverride = false

    public init() {}

    public var body: some Scene {
        WindowGroup {
            Group {
                if showContentView {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(supabaseManager)
                } else {
                    AuthView()
                        .environmentObject(supabaseManager)
                }
            }
            .task {
                await setupApp()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .continueOffline)
            ) { _ in
                offlineOverride = true
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    appState.showNewProjectSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("SLATE Info") {
                    appState.showAboutSheet = true
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    // MARK: - Auth gate logic

    /// Show ContentView when:
    ///   (a) user is authenticated, OR
    ///   (b) Supabase is not configured (offline mode), OR
    ///   (c) user explicitly pressed "Continue Offline"
    private var showContentView: Bool {
        supabaseManager.isAuthenticated
            || !supabaseManager.isConfigured
            || offlineOverride
    }

    // MARK: - App setup

    private func setupApp() async {
        NSWindow.allowsAutomaticWindowTabbing = false

        // Start the Supabase auth state listener (runs until the app exits).
        Task {
            await supabaseManager.startListeningToAuthState()
        }

        // Boot the ingest daemon and restore watch folders.
        let dbPath = GRDBClipStore.defaultDBPath()
        do {
            try await GRDBStore.shared.setup(at: dbPath)
            let daemon = try IngestDaemon(dbPath: dbPath)
            let watchFolders = try await GRDBStore.shared.allWatchFolders()
            for folder in watchFolders {
                try await daemon.addWatchFolder(folder)
            }
            appState.ingestDaemon = daemon
        } catch {
            appState.startupError = error.localizedDescription
        }
    }
}

// MARK: - App State

@MainActor
public class AppState: ObservableObject {
    @Published public var showNewProjectSheet: Bool = false
    @Published public var showAboutSheet: Bool      = false
    @Published public var selectedProject: Project?
    @Published public var startupError: String?

    public var ingestDaemon: IngestDaemon?

    public init() {}
}

// MARK: - User Model

public struct User: Codable, Identifiable {
    public let id: String
    public let email: String
    public let name: String?
    public let avatarURL: String?

    public init(id: String, email: String, name: String?, avatarURL: String?) {
        self.id       = id
        self.email    = email
        self.name     = name
        self.avatarURL = avatarURL
    }
}
