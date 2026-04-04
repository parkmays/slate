// SLATE — WatchFolderSheet
// Owned by: Claude Code
//
// Sheet for registering a new watch folder.  The user picks a directory via
// NSOpenPanel (or drags a folder onto the drop zone) and selects the project
// it belongs to.  On confirm the WatchFolder is persisted via GRDBStore and
// registered with the live IngestDaemon.

import AppKit
import IngestDaemon
import SwiftUI
import SLATECore
import SLATESharedTypes

public struct WatchFolderSheet: View {
    let project: Project
    @ObservedObject var projectStore: ProjectStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPath: String = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var isDroppingOver = false

    public init(project: Project, projectStore: ProjectStore) {
        self.project = project
        self.projectStore = projectStore
    }

    public var body: some View {
        VStack(spacing: 24) {
            Text("Add Watch Folder")
                .font(.headline)

            // Drop zone / path selector
            dropZone

            // Project picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Project")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(project.name)
                    .font(.subheadline)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add Folder") { addWatchFolder() }
                    .keyboardShortcut(.return)
                    .disabled(!canAdd || isAdding)
            }
        }
        .padding(24)
        .frame(width: 480, height: 320)
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDroppingOver ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isDroppingOver ? Color.accentColor.opacity(0.06) : Color.clear)
                )
                .frame(height: 100)

            if selectedPath.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("Drop a folder here or")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Choose Folder…") { chooseFolderPanel() }
                        .font(.caption)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentColor)
                    Text(selectedPath)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        selectedPath = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDroppingOver) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return }
                Task { @MainActor in selectedPath = url.path }
            }
            return true
        }
    }

    // MARK: - Helpers

    private var canAdd: Bool {
        !selectedPath.isEmpty
    }

    private func chooseFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Watch Folder"
        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
        }
    }

    private func addWatchFolder() {
        guard canAdd else { return }

        isAdding = true
        errorMessage = nil

        Task {
            do {
                let folder = try await projectStore.addWatchFolder(path: selectedPath, to: project)
                if let ingestDaemon = appState.ingestDaemon {
                    try await ingestDaemon.addWatchFolder(folder)
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAdding = false
                }
            }
        }
    }
}
