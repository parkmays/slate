import AppKit
import SwiftUI
import ExportWriters
import SLATECore
import SLATESharedTypes

struct AssemblyView: View {
    let project: Project
    @ObservedObject var clipStore: GRDBClipStore

    @EnvironmentObject private var supabaseManager: SupabaseManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var assemblyStore: AssemblyStore
    @State private var assemblyName = ""
    @State private var selectedScene = "All Scenes"
    @State private var selectedSubjectIds: [String] = []
    @State private var selectedTopicTags: [String] = []
    @State private var selectedExportFormat: ExportFormat = .fcpxml
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var exportSuccess: String?
    @State private var exportedFileURL: URL?

    init(project: Project, clipStore: GRDBClipStore) {
        self.project = project
        self.clipStore = clipStore
        _assemblyStore = StateObject(wrappedValue: AssemblyStore())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            editor
        } detail: {
            preview
        }
        .frame(minWidth: 1180, minHeight: 760)
        .task {
            await assemblyStore.load(project: project)
            if assemblyStore.currentAssembly == nil, !projectClips.isEmpty {
                await generateAssembly()
            } else {
                assemblyName = assemblyStore.currentAssembly?.name ?? ""
            }
        }
        .onChange(of: assemblyStore.currentAssembly?.id) {
            assemblyName = assemblyStore.currentAssembly?.name ?? ""
        }
    }

    private var sidebar: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                    Text(project.mode.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Assemblies") {
                if assemblyStore.assemblies.isEmpty {
                    Text("No assemblies yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(assemblyStore.assemblies) { assembly in
                        Button {
                            Task {
                                try? await assemblyStore.selectAssembly(assembly)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(assembly.name)
                                        .font(.subheadline.weight(.medium))
                                    Text("v\(assembly.version) • \(assembly.clips.count) clips")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if assemblyStore.currentAssembly?.id == assembly.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Versions") {
                if assemblyStore.versions.isEmpty {
                    Text("Export a version to recall it here.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(assemblyStore.versions) { version in
                        Button {
                            Task {
                                try? await assemblyStore.recallVersion(version)
                                exportSuccess = "Recalled v\(version.version) from \(version.exportedAt)"
                                exportedFileURL = nil
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("v\(version.version) • \(version.format.displayName)")
                                    .font(.subheadline.weight(.medium))
                                Text(version.exportedAt)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                TextField("Assembly name", text: $assemblyName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Button("Generate") {
                    Task { await generateAssembly() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(projectClips.isEmpty)

                Button("Reset Order") {
                    Task { await generateAssembly(resetPreferredOrder: true) }
                }
                .buttonStyle(.bordered)
                .disabled(projectClips.isEmpty)

                Button {
                    presentSavePanelAndExport()
                } label: {
                    HStack(spacing: 5) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        }
                        Text(isExporting ? "Exporting…" : "Export Snapshot")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isExporting || currentAssembly == nil)
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Picker("Format", selection: $selectedExportFormat) {
                    ForEach(exportFormats, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            filtersSection

            if let error = assemblyStore.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            if let exportError {
                HStack(spacing: 6) {
                    Label(exportError, systemImage: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Spacer()
                    Button {
                        self.exportError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)
            }

            if let exportSuccess {
                HStack(spacing: 6) {
                    Label(exportSuccess, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Spacer()
                    if let exportedFileURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([exportedFileURL])
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                .padding(8)
                .background(Color.green.opacity(0.12))
                .cornerRadius(6)
            }

            if let assembly = currentAssembly, !assembly.clips.isEmpty {
                List {
                    ForEach(Array(assembly.clips.enumerated()), id: \.element.clipId) { _, assemblyClip in
                        if let clip = clipLookup[assemblyClip.clipId] {
                            AssemblyClipEditorRow(
                                clip: clip,
                                assemblyClip: assemblyClip,
                                moveUp: {
                                    guard let currentIndex = assemblyStore.currentAssembly?.clips.firstIndex(where: { $0.clipId == assemblyClip.clipId }),
                                          currentIndex > 0 else { return }
                                    try? assemblyStore.moveCurrentAssemblyClips(
                                        fromOffsets: IndexSet(integer: currentIndex),
                                        toOffset: currentIndex - 1
                                    )
                                },
                                moveDown: {
                                    guard let currentIndex = assemblyStore.currentAssembly?.clips.firstIndex(where: { $0.clipId == assemblyClip.clipId }),
                                          let count = assemblyStore.currentAssembly?.clips.count,
                                          currentIndex < count - 1 else { return }
                                    try? assemblyStore.moveCurrentAssemblyClips(
                                        fromOffsets: IndexSet(integer: currentIndex),
                                        toOffset: currentIndex + 2
                                    )
                                },
                                onTrimChange: { inPoint, outPoint in
                                    try? assemblyStore.updateTrim(
                                        for: assemblyClip.clipId,
                                        inPoint: inPoint,
                                        outPoint: outPoint
                                    )
                                }
                            )
                        }
                    }
                    .onMove { source, destination in
                        try? assemblyStore.moveCurrentAssemblyClips(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.inset)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(projectClips.isEmpty ? "No clips available" : "Generate an assembly to start editing.")
                        .font(.headline)
                    Text(projectClips.isEmpty ? "Ingest clips into this project first." : "SLATE will order the best candidates, then you can drag to reorder and trim each clip.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let assembly = currentAssembly {
                AssemblyPreviewPlayerView(assembly: assembly, clipsById: clipLookup)
                    .frame(maxWidth: .infinity)

                GroupBox("Assembly Summary") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Name", value: assembly.name)
                        LabeledContent("Version", value: "v\(assembly.version)")
                        LabeledContent("Clips", value: "\(assembly.clips.count)")
                        LabeledContent("Runtime", value: formatDuration(assembly.clips.reduce(0) { $0 + $1.duration }))
                        LabeledContent("Export Format", value: selectedExportFormat.displayName)
                    }
                    .font(.caption)
                }

                if let artifact = assemblyStore.lastExportArtifact {
                    GroupBox("Last Export") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Format", value: artifact.format.rawValue)
                            LabeledContent("File", value: artifact.filePath)
                            LabeledContent("Bytes", value: "\(artifact.byteCount)")
                        }
                        .font(.caption)
                        .textSelection(.enabled)
                    }
                }
            } else {
                Spacer()
                Text("Select or generate an assembly to preview it.")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
    }

    private var projectClips: [Clip] {
        clipStore.clips.filter { $0.projectId == project.id }
    }

    private var clipLookup: [String: Clip] {
        Dictionary(uniqueKeysWithValues: projectClips.map { ($0.id, $0) })
    }

    private var currentAssembly: Assembly? {
        assemblyStore.currentAssembly
    }

    private var exportFormats: [ExportFormat] {
        [.fcpxml, .cmx3600EDL, .aaf, .premiereXML, .davinciResolveXML, .assemblyArchive]
    }

    private var availableScenes: [String] {
        Array(Set(projectClips.compactMap { $0.narrativeMeta?.sceneNumber }))
            .sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }

    private var availableSubjects: [(id: String, name: String)] {
        Array(
            Dictionary(
                uniqueKeysWithValues: projectClips.compactMap { clip in
                    clip.documentaryMeta.map { ($0.subjectId, $0.subjectName) }
                }
            )
        )
        .sorted { $0.value.compare($1.value, options: [.numeric, .caseInsensitive]) == .orderedAscending }
        .map { ($0.key, $0.value) }
    }

    private var availableTopicTags: [String] {
        Array(Set(projectClips.flatMap { $0.documentaryMeta?.topicTags ?? [] }))
            .sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }

    @ViewBuilder
    private var filtersSection: some View {
        GroupBox("Filters") {
            switch project.mode {
            case .narrative:
                HStack {
                    Text("Scene")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Scene", selection: $selectedScene) {
                        Text("All Scenes").tag("All Scenes")
                        ForEach(availableScenes, id: \.self) { scene in
                            Text(scene).tag(scene)
                        }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
            case .documentary:
                VStack(alignment: .leading, spacing: 10) {
                    Menu {
                        ForEach(availableSubjects, id: \.id) { subject in
                            Button {
                                toggle(subject.id, in: &selectedSubjectIds)
                            } label: {
                                Label(
                                    subject.name,
                                    systemImage: selectedSubjectIds.contains(subject.id) ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    } label: {
                        Label(
                            selectedSubjectIds.isEmpty ? "All Subjects" : "\(selectedSubjectIds.count) subject(s)",
                            systemImage: "person.2"
                        )
                    }

                    Menu {
                        ForEach(availableTopicTags, id: \.self) { tag in
                            Button {
                                toggle(tag, in: &selectedTopicTags)
                            } label: {
                                Label(
                                    tag,
                                    systemImage: selectedTopicTags.contains(tag) ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    } label: {
                        Label(
                            selectedTopicTags.isEmpty ? "All Topics" : "\(selectedTopicTags.count) topic tag(s)",
                            systemImage: "tag"
                        )
                    }
                }
            }
        }
    }

    private func generateAssembly(resetPreferredOrder: Bool = false) async {
        do {
            let options = AssemblyGenerationOptions(
                name: assemblyName.isEmpty ? nil : assemblyName,
                sceneFilter: selectedScene == "All Scenes" ? nil : selectedScene,
                selectedSubjectIds: selectedSubjectIds,
                selectedTopicTags: selectedTopicTags,
                preferredClipOrder: resetPreferredOrder ? [] : (assemblyStore.currentAssembly?.clips.map(\.clipId) ?? [])
            )
            try await assemblyStore.generateAssembly(project: project, clips: projectClips, options: options)
            assemblyName = assemblyStore.currentAssembly?.name ?? assemblyName
            exportError = nil
            exportSuccess = nil
            exportedFileURL = nil
        } catch {
            assemblyStore.error = error
        }
    }

    /// Called synchronously from the button — shows NSSavePanel, then kicks off async export.
    @MainActor
    private func presentSavePanelAndExport() {
        guard let assembly = currentAssembly else { return }

        let dateStamp: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: Date())
        }()

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.showsTagField = false
        panel.nameFieldStringValue = "\(assembly.name) \(dateStamp).\(selectedExportFormat.fileExtension)"
        panel.message = "Choose where to save your \(selectedExportFormat.displayName) export"

        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let format = selectedExportFormat
        let clips  = projectClips
        Task {
            await performExport(clips: clips, format: format, to: destination)
        }
    }

    private func performExport(clips: [Clip], format: ExportFormat, to destination: URL) async {
        isExporting = true
        exportError = nil
        exportSuccess = nil
        exportedFileURL = nil
        defer { isExporting = false }

        do {
            // Export into a temporary scratch directory so the writer can name the file freely.
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("slate-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let artifact = try await assemblyStore.exportCurrentAssembly(
                clips: clips,
                format: format,
                outputDirectory: tempDir
            )

            // Move from writer's chosen filename to user's chosen destination.
            let sourceURL = URL(fileURLWithPath: artifact.filePath)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destination)

            exportedFileURL = destination
            exportSuccess   = "Exported \(destination.lastPathComponent)"

            // Auto-deliver notifications if the project is configured for it.
            // Fires iMessage / email / Slack to the project's notification targets.
            if project.autoDeliverOnAssembly, !project.notificationTargets.isEmpty {
                // Attempt to generate a web-portal share link via Supabase.
                // Falls back to the local export file URL if the edge function is unavailable
                // (e.g. no network, Supabase not configured). Callers see the file URL in
                // that case — still useful for same-machine workflows.
                let shareURL: URL
                if let jwt = supabaseManager.accessToken {
                    do {
                        let result = try await ShareLinkService.shared.generateShareLink(
                            projectId: project.id,
                            scope: .assembly,
                            role: .editor,
                            permissions: .fullAccess,
                            jwt: jwt
                        )
                        shareURL = URL(string: result.url) ?? destination
                    } catch {
                        print("[AssemblyView] Share link generation failed, falling back to local path: \(error)")
                        shareURL = destination
                    }
                } else {
                    shareURL = destination
                }
                Task {
                    await NotificationService.shared.deliver(
                        projectName: project.name,
                        shareURL: shareURL,
                        targets: project.notificationTargets
                    )
                }
            }

            // Auto-dismiss the success banner after 3 seconds.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if exportSuccess != nil {
                    exportSuccess = nil
                }
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func toggle(_ value: String, in array: inout [String]) {
        if let index = array.firstIndex(of: value) {
            array.remove(at: index)
        } else {
            array.append(value)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "0s"
    }
}

private struct AssemblyClipEditorRow: View {
    let clip: Clip
    let assemblyClip: AssemblyClip
    let moveUp: () -> Void
    let moveDown: () -> Void
    let onTrimChange: (Double, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(assemblyClip.sceneLabel)
                        .font(.subheadline.weight(.medium))
                    Text(URL(fileURLWithPath: clip.sourcePath).lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Button(action: moveUp) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(.borderless)

                    Button(action: moveDown) {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(.borderless)
                }
                ReviewStatusBadge(status: clip.reviewStatus)
            }

            HStack(spacing: 16) {
                TrimStepper(
                    title: "In",
                    value: assemblyClip.inPoint,
                    range: 0...max(assemblyClip.outPoint - trimStep, 0),
                    step: trimStep
                ) { newValue in
                    onTrimChange(newValue, assemblyClip.outPoint)
                }

                TrimStepper(
                    title: "Out",
                    value: assemblyClip.outPoint,
                    range: min(max(assemblyClip.inPoint + trimStep, trimStep), clip.duration)...clip.duration,
                    step: trimStep
                ) { newValue in
                    onTrimChange(assemblyClip.inPoint, newValue)
                }

                Spacer()

                Text(assemblyClip.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var trimStep: Double {
        max(1.0 / max(clip.sourceFps, 1), 0.01)
    }
}

private struct TrimStepper: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onChange: (Double) -> Void

    var body: some View {
        Stepper(value: binding, in: range, step: step) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatTimecode(value))
                    .font(.caption.monospaced())
            }
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { value },
            set: { onChange($0) }
        )
    }

    private func formatTimecode(_ seconds: Double) -> String {
        let totalFrames = Int((seconds * 24).rounded())
        let hh = totalFrames / (24 * 3600)
        let mm = (totalFrames / (24 * 60)) % 60
        let ss = (totalFrames / 24) % 60
        let ff = totalFrames % 24
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }
}
