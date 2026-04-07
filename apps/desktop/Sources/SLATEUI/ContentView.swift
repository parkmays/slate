// SLATE — ContentView
// Owned by: Claude Code
//
// Main three-panel layout for the desktop app.
//
// C4 additions:
//   • Receives SupabaseManager as @EnvironmentObject so children
//     (ShareLinkSheet, ProxyPlayerView) can access the real JWT.
//   • Subscribes/unsubscribes realtime channels via supabaseManager.realtime
//     when the selected project or clip changes.
//   • Observes .realtimeClipIngested and .realtimeClipProxyReady to reload
//     the clip grid when new content arrives from the cloud.

import SwiftUI
import SLATECore
import SLATESharedTypes

public struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @StateObject private var clipStore: GRDBClipStore
    @StateObject private var projectStore: ProjectStore
    @StateObject private var syncManager: SyncManager
    @StateObject private var cloudSyncStore: CloudSyncStore
    @StateObject private var cloudAuthManager: CloudAuthManager
    @State private var selectedClip: Clip?
    @State private var multiCamGroupId: String?
    @State private var showingIngestProgress = false
    @State private var showingShareSheet = false
    @State private var showingAssemblySheet = false
    @State private var showingCloudSyncSheet = false
    @State private var showingColorSheet = false
    @State private var showingProductionSyncSheet = false
    @State private var isImportingMedia = false
    @State private var importNotice: String?

    public init() {
        let dbPath = GRDBClipStore.defaultDBPath()
        _clipStore    = StateObject(wrappedValue: GRDBClipStore(dbPath: dbPath))
        _projectStore = StateObject(wrappedValue: ProjectStore())
        _syncManager  = StateObject(wrappedValue: SyncManager())
        _cloudSyncStore = StateObject(wrappedValue: CloudSyncStore(dbPath: dbPath))
        _cloudAuthManager = StateObject(wrappedValue: CloudAuthManager())
    }

    public var body: some View {
        rootView
    }

    private var rootView: some View {
        VStack(spacing: 0) {
            if appState.startupError != nil || !supabaseManager.isConfigured {
                statusBanner
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }

            splitView
        }
        .toolbar {
            ContentToolbar(
                isConnected: syncManager.isConnected,
                hasSelectedProject: hasSelectedProject,
                hasSelectedClip: selectedClip != nil,
                showIngestProgress: { showingIngestProgress = true },
                showShareSheet: { showingShareSheet = true },
                showAssemblySheet: { showingAssemblySheet = true },
                showCloudSyncSheet: { showingCloudSyncSheet = true },
                showColorSheet: { showingColorSheet = true },
                showProductionSyncSheet: { showingProductionSyncSheet = true },
                showNewProjectSheet: { appState.showNewProjectSheet = true }
            )
        }
        .sheet(isPresented: $appState.showNewProjectSheet) {
            NewProjectSheet(projectStore: projectStore)
        }
        .sheet(isPresented: $showingIngestProgress) {
            IngestProgressView()
        }
        .sheet(isPresented: $appState.showAboutSheet) {
            AboutView()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let project = appState.selectedProject {
                ShareLinkSheet(project: project)
                    .environmentObject(supabaseManager)
            }
        }
        .sheet(isPresented: $showingAssemblySheet) {
            if let project = appState.selectedProject {
                AssemblyView(project: project, clipStore: clipStore)
                    .environmentObject(supabaseManager)
            }
        }
        .sheet(isPresented: $showingCloudSyncSheet) {
            if let project = appState.selectedProject {
                CloudSyncSheet(
                    project: project,
                    clipStore: clipStore,
                    projectStore: projectStore,
                    cloudSyncStore: cloudSyncStore,
                    cloudAuthManager: cloudAuthManager
                )
            }
        }
        .sheet(isPresented: $showingColorSheet) {
            if let clip = selectedClip {
                ColorGradeSheet(clip: clip, clipStore: clipStore)
            }
        }
        .sheet(isPresented: $showingProductionSyncSheet) {
            if let project = appState.selectedProject {
                ProductionSyncSheet(project: project, projectStore: projectStore, clipStore: clipStore)
            }
        }
        .alert(
            "Import Notice",
            isPresented: Binding(
                get: { importNotice != nil },
                set: { if !$0 { importNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importNotice ?? "")
        }
        .onReceive(clipStore.$projects) { projects in
            projectStore.setProjects(projects)
            let selectedId = appState.selectedProject?.id
            if let selectedId {
                let refreshed = projects.first { $0.id == selectedId }
                if let refreshed {
                    appState.selectedProject = refreshed
                }
            }
            if appState.selectedProject == nil {
                appState.selectedProject = projectStore.activeProject
                if let project = projectStore.activeProject {
                    Task {
                        await clipStore.selectProject(project)
                    }
                }
            }
            let store = clipStore
            Task {
                await ContentView.rescheduleDailyDigests(projects: projects, clipStore: store)
            }
        }
        .onReceive(clipStore.$clips) { clips in
            syncSelectedClip(with: clips)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipUpdated)) { _ in
            Task { await clipStore.reloadCurrentProject() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .realtimeClipIngested)
        ) { _ in
            Task { await clipStore.reloadCurrentProject() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .realtimeClipProxyReady)
        ) { _ in
            Task { await clipStore.reloadCurrentProject() }
        }
        .onChange(of: appState.selectedProject?.id) {
            let newProject = appState.selectedProject
            selectedClip = nil
            multiCamGroupId = nil
            Task {
                if let projectId = newProject?.id {
                    await supabaseManager.realtime.subscribeToProject(projectId)
                } else {
                    await supabaseManager.realtime.unsubscribeFromProject()
                }
            }
        }
        .onChange(of: selectedClip?.id) {
            let newClip = selectedClip
            Task {
                if let clipId = newClip?.id {
                    await supabaseManager.realtime.subscribeToClip(clipId)
                } else {
                    await supabaseManager.realtime.unsubscribeFromClip()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .multiCamNavigateToGroup)) { notification in
            if let gid = notification.userInfo?["groupId"] as? String {
                multiCamGroupId = gid
                if let clip = clipStore.clips(forGroupId: gid).first {
                    selectedClip = clip
                }
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebarColumn
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
    }

    private var sidebarColumn: some View {
        SidebarView(
            projectStore: projectStore,
            clipStore: clipStore,
            selectedProject: $appState.selectedProject
        )
        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
    }

    @ViewBuilder
    private var contentColumn: some View {
        if let project = appState.selectedProject {
            ClipGridView(
                project: project,
                clipStore: clipStore,
                selectedClip: $selectedClip,
                isImportingMedia: isImportingMedia,
                importDroppedURLs: importDroppedMedia,
                onSelectClip: { clip in
                    multiCamGroupId = nil
                    selectedClip = clip
                },
                onOpenMultiCamGroup: { groupId in
                    multiCamGroupId = groupId
                    if let clip = clipStore.clips(forGroupId: groupId).first {
                        selectedClip = clip
                    }
                }
            )
        } else {
            EmptyProjectView()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let groupId = multiCamGroupId {
            MultiCamPreviewView(
                groupId: groupId,
                clips: clipStore.clips(forGroupId: groupId),
                clipStore: clipStore,
                syncManager: syncManager,
                onClose: { multiCamGroupId = nil }
            )
            .environmentObject(supabaseManager)
        } else if let clip = selectedClip {
            ClipDetailView(clip: clip, syncManager: syncManager)
                .environmentObject(supabaseManager)
        } else {
            ClipSelectionPlaceholder()
        }
    }

    private var hasSelectedProject: Bool {
        appState.selectedProject != nil
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let startupError = appState.startupError {
            AppStatusBanner(
                title: "Startup Issue",
                message: "The app opened, but background services did not fully initialize: \(startupError)",
                tint: .red,
                systemImage: "exclamationmark.triangle.fill",
                dismiss: { appState.startupError = nil }
            )
        } else if !supabaseManager.isConfigured {
            AppStatusBanner(
                title: "Offline Mode",
                message: "Cloud sync and share links are disabled until SLATE_SUPABASE_URL and SLATE_SUPABASE_ANON_KEY are configured.",
                tint: .orange,
                systemImage: "wifi.slash",
                dismiss: nil
            )
        }
    }

    private func syncSelectedClip(with clips: [Clip]) {
        guard let selectedClip else {
            return
        }

        if let refreshedClip = clips.first(where: { $0.id == selectedClip.id }) {
            self.selectedClip = refreshedClip
        } else {
            self.selectedClip = nil
        }
    }

    private func importDroppedMedia(_ urls: [URL]) {
        guard let project = appState.selectedProject else {
            importNotice = "Create or select a project before importing media."
            return
        }

        showingIngestProgress = true
        isImportingMedia = true

        Task { @MainActor in
            defer { isImportingMedia = false }

            do {
                let result = try await projectStore.importMedia(from: urls, to: project)
                await clipStore.reloadCurrentProject()

                if let firstImportedClip = result.importedClips.first,
                   let refreshedClip = clipStore.clips.first(where: { $0.id == firstImportedClip.id }) {
                    selectedClip = refreshedClip
                }

                if !result.failedItems.isEmpty {
                    let failedSummary = result.failedItems
                        .prefix(3)
                        .map { "\($0.filename): \($0.message)" }
                        .joined(separator: "\n")
                    importNotice = """
                    Imported \(result.importedClips.count) item(s), but \(result.failedItems.count) failed.
                    \(failedSummary)
                    """
                }
            } catch {
                importNotice = error.localizedDescription
            }
        }
    }

    private static func rescheduleDailyDigests(projects: [Project], clipStore: GRDBClipStore) async {
        for p in projects {
            if p.dailyDigestEnabled, !p.digestTargets.isEmpty {
                await DigestService.shared.scheduleDailyDigest(for: p, sendAt: p.digestHour, clipStore: clipStore)
            } else {
                await DigestService.shared.cancelDigestSchedule(forProjectId: p.id)
            }
        }
    }
}

private struct ContentToolbar: ToolbarContent {
    let isConnected: Bool
    let hasSelectedProject: Bool
    let hasSelectedClip: Bool
    let showIngestProgress: () -> Void
    let showShareSheet: () -> Void
    let showAssemblySheet: () -> Void
    let showCloudSyncSheet: () -> Void
    let showColorSheet: () -> Void
    let showProductionSyncSheet: () -> Void
    let showNewProjectSheet: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            ConnectionStatusView(isConnected: isConnected)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showIngestProgress) {
                Image(systemName: "arrow.down.circle")
            }
            .help("Ingest Progress")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showShareSheet) {
                Image(systemName: "square.and.arrow.up")
            }
            .help(hasSelectedProject ? "Share Project" : "Select a project to share")
            .disabled(!hasSelectedProject)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showAssemblySheet) {
                Image(systemName: "film.stack")
            }
            .help(hasSelectedProject ? "Open Assembly Workspace" : "Select a project to build an assembly")
            .disabled(!hasSelectedProject)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showCloudSyncSheet) {
                Image(systemName: "icloud.and.arrow.up")
            }
            .help(hasSelectedProject ? "Open Cloud Sync" : "Select a project to configure cloud sync")
            .disabled(!hasSelectedProject)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showProductionSyncSheet) {
                Image(systemName: "link")
            }
            .help(hasSelectedProject ? "Production Sync (Airtable / ShotGrid)" : "Select a project")
            .disabled(!hasSelectedProject)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showColorSheet) {
                Image(systemName: "cube.transparent")
            }
            .help(hasSelectedClip ? "Custom proxy LUT (.cube) for selected clip" : "Select a clip to set a custom LUT")
            .disabled(!hasSelectedProject || !hasSelectedClip)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: showNewProjectSheet) {
                Image(systemName: "plus")
            }
            .help("New Project")
        }
    }
}

private struct ConnectionStatusView: View {
    let isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? .green : .orange)
            .frame(width: 8, height: 8)
            .help(isConnected ? "Connected" : "Offline-first mode")
    }
}

private struct EmptyProjectView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No Project Selected")
                .font(.title2)
                .fontWeight(.medium)
            Text("Select a project from the sidebar or create a new one to start reviewing dailies.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipSelectionPlaceholder: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No Clip Selected")
                .font(.title2)
                .fontWeight(.medium)
            Text("Select a clip from the middle panel to inspect sync, AI scores, and annotations.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppStatusBanner: View {
    let title: String
    let message: String
    let tint: Color
    let systemImage: String
    let dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(tint.opacity(0.22))
                )
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
            .environmentObject(SupabaseManager())
    }
}
