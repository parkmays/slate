// SLATE — Import production sound reports (CSV/PDF) and match to clips

import AppKit
import IngestDaemon
import SwiftUI
import UniformTypeIdentifiers
import SLATECore
import SLATESharedTypes

public struct SoundReportImportSheet: View {
    let project: Project
    @ObservedObject var clipStore: GRDBClipStore
    @Environment(\.dismiss) private var dismiss

    @State private var summaryText: String?
    @State private var errorText: String?
    @State private var isImporting = false

    public init(project: Project, clipStore: GRDBClipStore) {
        self.project = project
        self.clipStore = clipStore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Sound Report")
                .font(.headline)

            Text("Choose a CSV (e.g. Sound Devices MixPre) or PDF export. Entries are matched to clips by audio file name, timecode, or scene/take metadata.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let summaryText {
                Text(summaryText)
                    .font(.caption.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Choose File…") { chooseAndImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting)
            }
        }
        .padding(24)
        .frame(width: 440, height: 260)
    }

    private func chooseAndImport() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.allowedContentTypes = [
            .commaSeparatedText,
            .pdf,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText
        ]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        errorText = nil
        summaryText = nil

        Task {
            do {
                let dbPath = GRDBClipStore.defaultDBPath()
                try await GRDBStore.shared.setup(at: dbPath)

                let parser = SoundReportParser()
                let entries = try await parser.parse(fileURL: url)
                let projectClips = clipStore.clips.filter { $0.projectId == project.id }
                let results = parser.match(entries: entries, against: projectClips)
                try await parser.applyMatches(results, to: GRDBStore.shared)

                let matched = results.filter { $0.confidence >= 0.70 && $0.matchedClipId != nil }.count
                let circledInReport = entries.filter { $0.circled }.count

                await MainActor.run {
                    summaryText = "Matched \(matched)/\(entries.count) entries (\(circledInReport) circled in report)"
                    isImporting = false
                }
                await clipStore.loadClips()
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}
