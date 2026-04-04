// SLATE — ClipDetailView
// Owned by: Claude Code

import AVKit
import SwiftUI
import SLATECore
import SLATESharedTypes

public struct ClipDetailView: View {
    let clip: Clip
    @ObservedObject var syncManager: SyncManager

    @State private var selectedTab: DetailTab = .preview
    @State private var annotations: [Annotation] = []
    @State private var showingAnnotationEditor = false

    public var body: some View {
        VStack(spacing: 0) {
            ClipDetailHeader(clip: clip)
            Divider()
            Picker("Tab", selection: $selectedTab) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Label(tab.displayName, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case .preview:
                    ProxyPlayerView(clip: clip)
                        .padding(.vertical, 8)
                case .info:
                    ClipInfoView(clip: clip)
                case .sync:
                    ClipSyncView(clip: clip)
                case .aiScores:
                    ClipAIScoresView(clip: clip)
                case .annotations:
                    ClipAnnotationsView(annotations: annotations) {
                        showingAnnotationEditor = true
                    }
                }
            }
        }
        .onAppear {
            let currentAnnotations = syncManager.getAnnotations(forClipId: clip.id, fallback: clip.annotations)
            annotations = currentAnnotations
            syncManager.primeAnnotations(currentAnnotations, forClipId: clip.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .annotationAdded)) { notification in
            guard notification.userInfo?["clipId"] as? String == clip.id,
                  let annotation = notification.object as? Annotation else {
                return
            }
            annotations.append(annotation)
        }
        .onReceive(NotificationCenter.default.publisher(for: .annotationUpdated)) { notification in
            guard notification.userInfo?["clipId"] as? String == clip.id,
                  let annotation = notification.object as? Annotation,
                  let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
                return
            }
            annotations[index] = annotation
        }
        .onReceive(NotificationCenter.default.publisher(for: .annotationDeleted)) { notification in
            guard notification.userInfo?["clipId"] as? String == clip.id,
                  let annotationId = notification.userInfo?["annotationId"] as? String else {
                return
            }
            annotations.removeAll { $0.id == annotationId }
        }
        .sheet(isPresented: $showingAnnotationEditor) {
            AnnotationEditorSheet { type, body in
                let annotation = Annotation(
                    userId: "local-user",
                    userDisplayName: "Current User",
                    timecodeIn: "00:00:00:00",
                    body: body,
                    type: type
                )
                Task {
                    try? await syncManager.addAnnotation(to: clip.id, annotation: annotation)
                }
            }
        }
    }
}

private enum DetailTab: CaseIterable {
    case preview
    case info
    case sync
    case aiScores
    case annotations

    var displayName: String {
        switch self {
        case .preview: return "Preview"
        case .info: return "Info"
        case .sync: return "Sync"
        case .aiScores: return "AI Scores"
        case .annotations: return "Annotations"
        }
    }

    var iconName: String {
        switch self {
        case .preview: return "play.rectangle"
        case .info: return "info.circle"
        case .sync: return "arrow.triangle.2.circlepath"
        case .aiScores: return "brain"
        case .annotations: return "bubble.left.and.bubble.right"
        }
    }
}

private struct ClipDetailHeader: View {
    let clip: Clip

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: clip.sourcePath).lastPathComponent)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(clip.sourceFormat.rawValue)
                    Text("•")
                    Text("\(clip.sourceFps, specifier: "%.2f") fps")
                    Text("•")
                    Text(formatDuration(clip.duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ReviewStatusBadge(status: clip.reviewStatus)
                ProxyStatusBadge(status: clip.proxyStatus)
            }
        }
        .padding()
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "00:00"
    }
}

private struct ClipInfoView: View {
    let clip: Clip

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("File Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Path", value: clip.sourcePath)
                        InfoRow(label: "Size", value: formatFileSize(clip.sourceSize))
                        InfoRow(label: "Format", value: clip.sourceFormat.rawValue)
                        InfoRow(label: "Checksum", value: clip.checksum)
                        InfoRow(label: "Ingested", value: clip.ingestedAt)
                    }
                }

                if let narrative = clip.narrativeMeta {
                    GroupBox("Narrative") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Scene", value: narrative.sceneNumber)
                            InfoRow(label: "Shot", value: narrative.shotCode)
                            InfoRow(label: "Take", value: "\(narrative.takeNumber)")
                            InfoRow(label: "Camera", value: narrative.cameraId)
                        }
                    }
                }

                if let documentary = clip.documentaryMeta {
                    GroupBox("Documentary") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Subject", value: documentary.subjectName)
                            InfoRow(label: "Day", value: "\(documentary.shootingDay)")
                            InfoRow(label: "Session", value: documentary.sessionLabel)
                        }
                    }
                }

                GroupBox("Proxy") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Status", value: clip.proxyStatus.rawValue)
                        if let proxyPath = clip.proxyPath {
                            InfoRow(label: "Path", value: proxyPath)
                        }
                        if let proxyChecksum = clip.proxyChecksum {
                            InfoRow(label: "Checksum", value: proxyChecksum)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

private struct ClipSyncView: View {
    let clip: Clip

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox("Sync Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Confidence", value: clip.syncResult.confidence.displayName)
                        InfoRow(label: "Method", value: clip.syncResult.method.rawValue)
                        InfoRow(label: "Offset", value: "\(clip.syncResult.offsetFrames) frames")
                        InfoRow(label: "Drift", value: "\(Int(clip.syncResult.driftPPM.rounded())) ppm")
                        if let verifiedAt = clip.syncResult.verifiedAt {
                            InfoRow(label: "Verified", value: verifiedAt)
                        }
                    }
                }

                GroupBox("Sync Assessment") {
                    Label(clip.syncResult.confidence.detailLabel, systemImage: clip.syncResult.confidence.iconName)
                        .foregroundColor(clip.syncResult.confidence.color)
                        .font(.caption)
                }
            }
            .padding()
        }
    }
}

private struct ClipAIScoresView: View {
    let clip: Clip

    var body: some View {
        ScrollView {
            if let scores = clip.aiScores {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox("Scores") {
                        VStack(spacing: 12) {
                            ScoreRow(label: "Focus", score: scores.focus, color: .blue)
                            ScoreRow(label: "Exposure", score: scores.exposure, color: .green)
                            ScoreRow(label: "Stability", score: scores.stability, color: .orange)
                            ScoreRow(label: "Audio", score: scores.audio, color: .purple)
                            if let performance = scores.performance {
                                ScoreRow(label: "Performance", score: performance, color: .pink)
                            }
                            if let contentDensity = scores.contentDensity {
                                ScoreRow(label: "Content Density", score: contentDensity, color: .teal)
                            }
                            Divider()
                            ScoreRow(label: "Composite", score: scores.composite, color: .primary, isBold: true)
                        }
                    }

                    GroupBox("Reasoning") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(scores.reasoning.enumerated()), id: \.offset) { _, reason in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(reason.dimension)
                                            .font(.caption.bold())
                                        Spacer()
                                        Text(reason.flag.rawValue.capitalized)
                                            .font(.caption2)
                                            .foregroundColor(reason.flag.color)
                                    }
                                    Text(reason.message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let timecode = reason.timecode {
                                        Text(timecode)
                                            .font(.caption.monospaced())
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    GroupBox("Analysis Information") {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "Model", value: scores.modelVersion)
                            InfoRow(label: "Scored", value: scores.scoredAt)
                        }
                    }
                }
                .padding()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "brain")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("AI Analysis Pending")
                        .font(.headline)
                    Text("AI scores will appear after sync and proxy analysis complete.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

private struct ScoreRow: View {
    let label: String
    let score: Double
    let color: Color
    let isBold: Bool

    init(label: String, score: Double, color: Color, isBold: Bool = false) {
        self.label = label
        self.score = score
        self.color = color
        self.isBold = isBold
    }

    var body: some View {
        HStack {
            Text(label)
                .font(isBold ? .caption.bold() : .caption)
                .frame(width: 110, alignment: .leading)
            ProgressView(value: score / 100)
                .tint(color)
            Text(String(format: "%.0f", score))
                .font(isBold ? .caption.bold() : .caption)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct ClipAnnotationsView: View {
    let annotations: [Annotation]
    let onAddAnnotation: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if annotations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No Annotations")
                            .font(.headline)
                        Text("Add annotations to mark important moments or leave feedback.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(annotations.sorted { $0.timecodeIn < $1.timecodeIn }) { annotation in
                            AnnotationRowView(annotation: annotation)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }

            Divider()

            HStack {
                Button(action: onAddAnnotation) {
                    Label("Add Annotation", systemImage: "plus.bubble")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
        }
    }
}

private struct AnnotationRowView: View {
    let annotation: Annotation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: annotation.type.iconName)
                    .foregroundColor(annotation.type == .voice ? .orange : .blue)
                Text(annotation.timecodeIn)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                Text(annotation.userDisplayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let resolvedAt = annotation.resolvedAt {
                    Text("Resolved \(resolvedAt)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Text(annotation.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

private struct AnnotationEditorSheet: View {
    let onSave: (AnnotationType, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: AnnotationType = .text
    @State private var bodyText = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Annotation")
                .font(.headline)

            Picker("Type", selection: $selectedType) {
                ForEach(AnnotationType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.iconName)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $bodyText)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    onSave(selectedType, bodyText)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 420, height: 300)
    }
}

private extension SyncConfidence {
    var displayName: String {
        rawValue
    }

    var detailLabel: String {
        switch self {
        case .high: return "Excellent (<= 0.5 frames)"
        case .medium: return "Good (<= 2 frames)"
        case .low: return "Fair (<= 5 frames)"
        case .manualRequired: return "Manual sync required"
        case .unsynced: return "Not yet synced"
        }
    }

    var iconName: String {
        switch self {
        case .high: return "checkmark.circle.fill"
        case .medium: return "checkmark.circle"
        case .low: return "exclamationmark.triangle"
        case .manualRequired: return "xmark.circle.fill"
        case .unsynced: return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        case .manualRequired: return .red
        case .unsynced: return .gray
        }
    }
}

private extension ScoreFlag {
    var color: Color {
        switch self {
        case .info: return .gray
        case .warning: return .orange
        case .error: return .red
        }
    }
}
