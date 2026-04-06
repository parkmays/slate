// SLATE — SidebarView
// Owned by: Claude Code

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SLATECore
import SLATESharedTypes

public struct SidebarView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var clipStore: GRDBClipStore
    @Binding var selectedProject: Project?

    @State private var searchText = ""
    @State private var showingNewProjectSheet = false
    @State private var watchFolderProject: Project?
    @State private var soundReportProject: Project?
    @State private var scriptImportNotice: String?
    @State private var scriptImportError: String?

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "film.stack")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button {
                        showingNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Project")
                }

                TextField("Search projects...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Group {
                if projectStore.projects.isEmpty {
                    VStack(spacing: 12) {
                        Text("No Projects")
                            .font(.headline)
                        Text("Create a project to start browsing synced clips.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredProjects) { project in
                                ProjectRowView(
                                    project: project,
                                    isSelected: selectedProject?.id == project.id,
                                    statistics: clipStore.statistics(for: project.id),
                                    onSelect: {
                                        selectedProject = project
                                        projectStore.setActiveProject(project)
                                        Task {
                                            await clipStore.selectProject(project)
                                        }
                                    },
                                    onAddWatchFolder: {
                                        watchFolderProject = project
                                    },
                                    onImportSoundReport: {
                                        soundReportProject = project
                                    },
                                    onImportScript: {
                                        presentScriptImportPanel(for: project)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }

            Spacer()

            if let project = selectedProject {
                Divider()
                HStack {
                    Button {
                        soundReportProject = project
                    } label: {
                        Label("Import Sound Report…", systemImage: "waveform")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        presentScriptImportPanel(for: project)
                    } label: {
                        Label("Import Script…", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 6)
                SceneSubjectListView(project: project, clipStore: clipStore)
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet(projectStore: projectStore)
        }
        .sheet(item: $watchFolderProject) { project in
            WatchFolderSheet(project: project, projectStore: projectStore, clipStore: clipStore)
        }
        .sheet(item: $soundReportProject) { project in
            SoundReportImportSheet(project: project, clipStore: clipStore)
        }
        .alert("Script imported", isPresented: Binding(
            get: { scriptImportNotice != nil },
            set: { if !$0 { scriptImportNotice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let scriptImportNotice {
                Text(scriptImportNotice)
            }
        }
        .alert("Import failed", isPresented: Binding(
            get: { scriptImportError != nil },
            set: { if !$0 { scriptImportError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let scriptImportError {
                Text(scriptImportError)
            }
        }
    }

    private func presentScriptImportPanel(for project: Project) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Screenplay"
        var types: [UTType] = [.pdf]
        if let fdx = UTType(filenameExtension: "fdx") {
            types.append(fdx)
        }
        panel.allowedContentTypes = types
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let result = try await clipStore.importScript(from: url, projectId: project.id)
                    let title = result.title ?? url.deletingPathExtension().lastPathComponent
                    scriptImportNotice = "Imported \(result.scenes.count) scenes from \(title).\(url.pathExtension.lowercased())"
                } catch {
                    scriptImportError = error.localizedDescription
                }
            }
        }
    }

    private var filteredProjects: [Project] {
        guard !searchText.isEmpty else {
            return projectStore.projects
        }
        return projectStore.projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct ProjectRowView: View {
    let project: Project
    let isSelected: Bool
    let statistics: ProjectStatistics
    let onSelect: () -> Void
    let onAddWatchFolder: () -> Void
    let onImportSoundReport: () -> Void
    let onImportScript: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(project.mode == .narrative ? Color.blue.opacity(0.16) : Color.green.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: project.mode == .narrative ? "film" : "video")
                        .foregroundColor(project.mode == .narrative ? .blue : .green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.system(size: 14, weight: .medium))
                    HStack(spacing: 8) {
                        Text(project.mode.rawValue.capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.18))
                            .cornerRadius(4)
                        Text("\(statistics.totalClips) clips")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onImportSoundReport) {
                    Image(systemName: "waveform")
                }
                .buttonStyle(.borderless)
                .help("Import Sound Report")

                Button(action: onImportScript) {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(.borderless)
                .help("Import Script")

                VStack(spacing: 2) {
                    ProgressView(value: statistics.reviewProgress)
                        .frame(width: 40)
                    Text("\(Int(statistics.reviewProgress * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Add Watch Folder", action: onAddWatchFolder)
            Button("Import Sound Report…", action: onImportSoundReport)
            Button("Import Script…", action: onImportScript)
        }
    }
}

private struct SceneSubjectListView: View {
    let project: Project
    @ObservedObject var clipStore: GRDBClipStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.mode == .narrative ? "Scenes" : "Subjects")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(groupedItems.keys.sorted(), id: \.self) { key in
                        GroupRowView(
                            title: key,
                            count: groupedItems[key]?.count ?? 0,
                            projectMode: project.mode
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 200)
        }
    }

    private var groupedItems: [String: [Clip]] {
        project.mode == .narrative ? clipStore.groupedNarrativeClips : clipStore.groupedDocumentaryClips
    }
}

private struct GroupRowView: View {
    let title: String
    let count: Int
    let projectMode: ProjectMode

    var body: some View {
        HStack {
            Image(systemName: projectMode == .narrative ? "folder" : "person.crop.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(title)
                .font(.caption)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.18))
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct SidebarView_Previews: PreviewProvider {
    static var previews: some View {
        SidebarView(
            projectStore: ProjectStore(),
            clipStore: GRDBClipStore(dbPath: NSTemporaryDirectory() + "/slate-preview.db"),
            selectedProject: .constant(nil)
        )
    }
}
