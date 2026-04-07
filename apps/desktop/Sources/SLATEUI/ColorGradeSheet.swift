import IngestDaemon
import SLATECore
import SLATESharedTypes
import SwiftUI
import UniformTypeIdentifiers

/// Assign a custom `.cube` LUT for proxy baking (stored on the clip as `custom_cube` + path).
public struct ColorGradeSheet: View {
    private let clip: Clip
    private let clipStore: GRDBClipStore

    @Environment(\.dismiss) private var dismiss
    @State private var customPath: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var showImporter = false

    public init(clip: Clip, clipStore: GRDBClipStore) {
        self.clip = clip
        self.clipStore = clipStore
        _customPath = State(initialValue: clip.customProxyLUTPath ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Color / LUT")
                .font(.title2)
            Text("Choose a Rec.709-oriented `.cube` LUT to bake into new proxies for this clip. After saving, regenerate the proxy (re-run ingest for the source) to apply.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Path to .cube file", text: $customPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { showImporter = true }
            }

            HStack {
                Button("Clear custom LUT") {
                    Task { await saveCustomLUT(path: nil) }
                }
                .disabled(isSaving)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    Task { await saveCustomLUT(path: customPath.isEmpty ? nil : customPath) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(24)
        .frame(minWidth: 480)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "cube") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    customPath = url.path
                }
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }

    private func saveCustomLUT(path: String?) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        if let path, !path.isEmpty, !FileManager.default.fileExists(atPath: path) {
            errorMessage = "File does not exist at path."
            return
        }

        do {
            let dbPath = GRDBClipStore.defaultDBPath()
            try await GRDBStore.shared.setup(at: dbPath)

            var updated = clip
            let now = ISO8601DateFormatter().string(from: Date())
            updated.updatedAt = now
            if let path, !path.isEmpty {
                updated.proxyLUT = "custom_cube"
                updated.customProxyLUTPath = path
            } else {
                updated.proxyLUT = nil
                updated.customProxyLUTPath = nil
            }

            try await GRDBStore.shared.saveClip(updated)
            await clipStore.reloadCurrentProject()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
