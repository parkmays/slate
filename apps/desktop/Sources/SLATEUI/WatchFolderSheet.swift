// SLATE — WatchFolderSheet
// Owned by: Claude Code
//
// Sheet for registering a new watch folder.  The user picks a directory via
// NSOpenPanel (or drags a folder onto the drop zone) and selects the project
// it belongs to.  On confirm the WatchFolder is persisted via GRDBStore and
// registered with the live IngestDaemon.
//
// Includes Daily Digest settings (separate from per-assembly notification targets).

import AppKit
import IngestDaemon
import SwiftUI
import SLATECore
import SLATESharedTypes

public struct WatchFolderSheet: View {
    let project: Project
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var clipStore: GRDBClipStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPath: String = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var isDroppingOver = false
    @State private var uploadThrottleText = ""
    @State private var transcodeScaleDivisorText = "4"
    @State private var transcodeBitrateText = "8000000"
    @State private var watermarkOpacityText = "0.85"

    @State private var digestEnabled = false
    @State private var digestHour = 21
    @State private var digestTargets: [DeliveryTarget] = []
    @State private var newTargetName = ""
    @State private var newTargetAddress = ""
    @State private var newTargetMethod: DeliveryMethod = .email

    public init(project: Project, projectStore: ProjectStore, clipStore: GRDBClipStore) {
        self.project = project
        self.projectStore = projectStore
        self.clipStore = clipStore
    }

    public var body: some View {
        VStack(spacing: 20) {
            Text("Add Watch Folder")
                .font(.headline)

            dropZone

            VStack(alignment: .leading, spacing: 6) {
                Text("Project")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(project.name)
                    .font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Upload throttle (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("Unlimited", text: $uploadThrottleText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                    Text("bytes/sec for R2 proxy upload")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom transcode profile")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack {
                    TextField("Scale divisor", text: $transcodeScaleDivisorText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    TextField("Bitrate (bps)", text: $transcodeBitrateText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField("Watermark opacity", text: $watermarkOpacityText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                }
                Text("Example: divisor 4, bitrate 8000000, opacity 0.85")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            dailyDigestSection

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer(minLength: 8)

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
        .frame(width: 520, height: 560)
        .onAppear {
            digestEnabled = project.dailyDigestEnabled
            digestHour = min(23, max(0, project.digestHour))
            digestTargets = project.digestTargets
        }
    }

    // MARK: - Daily digest

    private var dailyDigestSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Digest")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Send end-of-day summary while SLATE is running", isOn: $digestEnabled)
                    .onChange(of: digestEnabled) { _, _ in persistDigestSettings() }

                HStack {
                    Text("Send at")
                    Picker("", selection: $digestHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(hourLabel(h)).tag(h)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .onChange(of: digestHour) { _, _ in persistDigestSettings() }

                    Text("local time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Text("Recipients (separate from assembly notifications)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if digestTargets.isEmpty {
                    Text("No digest recipients yet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(digestTargets.enumerated()), id: \.offset) { index, target in
                        HStack {
                            Text(target.method.rawValue)
                                .font(.caption.monospaced())
                                .frame(width: 72, alignment: .leading)
                            Text(target.name)
                                .font(.caption)
                            Spacer()
                            Text(target.address)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Button {
                                digestTargets.remove(at: index)
                                persistDigestSettings()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    TextField("Label", text: $newTargetName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Picker("", selection: $newTargetMethod) {
                        Text("Email").tag(DeliveryMethod.email)
                        Text("Slack").tag(DeliveryMethod.slack)
                    }
                    .frame(width: 100)
                    TextField(newTargetMethod == .email ? "email@…" : "Webhook URL", text: $newTargetAddress)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let name = newTargetName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let addr = newTargetAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !addr.isEmpty else { return }
                        digestTargets.append(DeliveryTarget(name: name, method: newTargetMethod, address: addr))
                        newTargetName = ""
                        newTargetAddress = ""
                        persistDigestSettings()
                    }
                    .disabled(newTargetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTargetAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        String(format: "%02d:00", h)
    }

    private func persistDigestSettings() {
        var updated = project
        updated.digestTargets = digestTargets
        updated.digestHour = digestHour
        updated.dailyDigestEnabled = digestEnabled
        projectStore.persistProjectDeliverySettings(updated, clipStore: clipStore)
        if appState.selectedProject?.id == project.id {
            appState.selectedProject = updated
        }
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
                let throttle = Int(uploadThrottleText.trimmingCharacters(in: .whitespacesAndNewlines))
                let scaleDivisor = Int(transcodeScaleDivisorText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 4
                let bitrate = Int(transcodeBitrateText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8_000_000
                let opacity = Double(watermarkOpacityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.85
                let profile = ProxyTranscodeProfile(
                    name: "Custom \(project.name)",
                    scaleDivisor: scaleDivisor,
                    bitrateBps: bitrate,
                    watermarkOpacity: opacity
                )
                let folder = try await projectStore.addWatchFolder(
                    path: selectedPath,
                    to: project,
                    uploadThrottleBytesPerSecond: (throttle ?? 0) > 0 ? throttle : nil,
                    transcodeProfile: profile
                )
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
