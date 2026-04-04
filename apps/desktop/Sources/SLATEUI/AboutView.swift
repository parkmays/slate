import SwiftUI
import SLATECore

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var updateManager = UpdateManager()

    private let processInfo = ProcessInfo.processInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            capabilities
            updateCard

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
        }
        .padding(24)
        .frame(width: 520, height: 500)
        .task {
            if updateManager.configuredFeedURL != nil, updateManager.latestRelease == nil, !updateManager.checking {
                await updateManager.checkForUpdates()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.85), Color.blue.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)

                Image(systemName: "film.stack.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SLATE")
                    .font(.largeTitle.weight(.bold))
                Text("Offline-first dailies review for narrative and documentary teams.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Version \(updateManager.currentVersion) • Build \(updateManager.currentBuild)")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private var capabilities: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Capabilities")
                .font(.headline)

            AboutCapabilityRow(
                title: "AI Pipeline",
                value: processInfo.environment["SLATE_GEMMA_ENABLED"] == "1"
                    ? "Local visual/audio scoring, Apple Speech fallback, and Gemma 4 insight"
                    : "Local visual/audio scoring with Apple Speech and heuristic transcript fallback"
            )

            AboutCapabilityRow(
                title: "Cloud Providers",
                value: "Google Drive, Dropbox, and Frame.io with push + pull sync for footage, edits, and comments"
            )

            AboutCapabilityRow(
                title: "Supabase",
                value: isSupabaseConfigured
                    ? "Configured for auth, review links, and realtime collaboration"
                    : "Running in offline-first mode until Supabase env vars are set"
            )
        }
        .padding(18)
        .background(aboutCardBackground)
    }

    private var updateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release Channel")
                        .font(.headline)
                    Text("Use a JSON appcast feed for manual update checks, then notarize and publish signed app bundles or DMGs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if updateManager.checking {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let latestRelease = updateManager.latestRelease {
                AboutCapabilityRow(
                    title: updateManager.updateAvailable ? "Update Available" : "Up To Date",
                    value: "\(latestRelease.version) (\(latestRelease.build))"
                )

                if let publishedAt = latestRelease.publishedAt, !publishedAt.isEmpty {
                    AboutCapabilityRow(title: "Published", value: publishedAt)
                }

                if let notesURL = latestRelease.releaseNotesURL,
                   let url = URL(string: notesURL) {
                    Link("Open Release Notes", destination: url)
                        .font(.caption.weight(.medium))
                }

                if let downloadURL = URL(string: latestRelease.downloadURL) {
                    Link("Open Download", destination: downloadURL)
                        .font(.caption.weight(.medium))
                }
            } else if let errorMessage = updateManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No update feed is configured yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await updateManager.checkForUpdates()
                    }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.borderedProminent)

                if let feedURL = updateManager.configuredFeedURL {
                    Link("Open Feed", destination: feedURL)
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(18)
        .background(aboutCardBackground)
    }

    private var isSupabaseConfigured: Bool {
        let env = processInfo.environment
        let url = env["SLATE_SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let anonKey = env["SLATE_SUPABASE_ANON_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !url.isEmpty && !anonKey.isEmpty
    }

    private var aboutCardBackground: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.secondary.opacity(0.14))
            )
    }
}

private struct AboutCapabilityRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
