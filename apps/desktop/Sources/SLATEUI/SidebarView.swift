// SLATE — SidebarView
// Owned by: Claude Code

import SwiftUI
import SLATECore
import SLATESharedTypes

public struct SidebarView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var clipStore: GRDBClipStore
    @Binding var selectedProject: Project?

    @State private var searchText = ""
    @State private var showingNewProjectSheet = false
    @State private var watchFolderProject: Project?

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
                SceneSubjectListView(project: project, clipStore: clipStore)
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectSheet(projectStore: projectStore)
        }
        .sheet(item: $watchFolderProject) { project in
            WatchFolderSheet(project: project, projectStore: projectStore)
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
