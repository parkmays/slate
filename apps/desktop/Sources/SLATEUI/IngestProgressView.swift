// SLATE — IngestProgressView
// Owned by: Claude Code

import SwiftUI
import SLATECore
import SLATESharedTypes

struct IngestProgressView: View {
    @Environment(\.dismiss) private var dismiss
    /// Uses the XPC-backed IPCManager rather than in-process NotificationCenter.
    /// The daemon pushes progress over XPC; IPCManager.displayReport bridges to
    /// the IngestProgressReport the UI already knows how to render.
    @ObservedObject private var ipc = IPCManager.shared

    private var report: IngestProgressReport { ipc.displayReport }

    private var overallProgress: Double {
        guard !report.active.isEmpty else { return 0 }
        return report.active.map(\.progress).reduce(0, +) / Double(report.active.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ingest Progress")
                    .font(.headline)
                Spacer()
                // Connection indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(ipc.isConnected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(ipc.isConnected ? "Daemon connected" : "Daemon offline")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .padding(.leading, 8)
            }
            .padding()

            Divider()

            if report.active.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Active Ingest")
                        .font(.headline)
                    Text("Files will appear here as watch folders dispatch new media into ingest.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(report.active, id: \.filename) { item in
                            IngestProgressRow(item: item)
                            Divider()
                        }
                    }
                    .padding()
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Summary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(report.active.count) active, \(report.queued) queued")
                            .font(.caption)
                    }
                    Spacer()
                    ProgressView(value: overallProgress)
                        .frame(width: 120)
                }
                .padding()
            }
        }
        .frame(width: 520, height: 420)
    }
}

private struct IngestProgressRow: View {
    let item: IngestProgressItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.stage.iconName)
                .foregroundColor(item.stage.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(.body)
                    .lineLimit(1)
                Text(item.stage.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: item.progress)
                    .frame(width: 100)
                Text("\(Int(item.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private extension IngestStage {
    var description: String {
        switch self {
        case .checksum: return "Calculating checksum"
        case .copy: return "Copying source"
        case .verify: return "Verifying media"
        case .proxy: return "Generating proxy"
        case .sync: return "Running sync and AI scoring"
        case .complete: return "Complete"
        case .error: return "Error"
        }
    }

    var iconName: String {
        switch self {
        case .checksum: return "checkmark.circle"
        case .copy: return "doc.on.doc"
        case .verify: return "shield.checkerboard"
        case .proxy: return "video"
        case .sync: return "waveform.path.ecg"
        case .complete: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .checksum: return .blue
        case .copy: return .green
        case .verify: return .orange
        case .proxy: return .purple
        case .sync: return .teal
        case .complete: return .green
        case .error: return .red
        }
    }
}

struct NewProjectSheet: View {
    @ObservedObject var projectStore: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var projectMode: ProjectMode = .narrative
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("New Project")
                .font(.headline)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter project name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Mode", selection: $projectMode) {
                    Text("Narrative").tag(ProjectMode.narrative)
                    Text("Documentary").tag(ProjectMode.documentary)
                }
                .pickerStyle(.segmented)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                Spacer()
                Button("Create") {
                    createProject()
                }
                .keyboardShortcut(.return)
                .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding()
        .frame(width: 420, height: 260)
    }

    private func createProject() {
        errorMessage = nil
        isCreating = true
        Task {
            do {
                _ = try await projectStore.createProject(name: projectName, mode: projectMode)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
