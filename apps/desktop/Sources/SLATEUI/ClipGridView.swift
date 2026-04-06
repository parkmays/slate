// SLATE — ClipGridView
// Owned by: Claude Code

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
import SLATECore
import SLATESharedTypes

public struct ClipGridView: View {
    let project: Project
    @ObservedObject var clipStore: GRDBClipStore
    @Binding var selectedClip: Clip?
    let isImportingMedia: Bool
    let importDroppedURLs: ([URL]) -> Void
    /// Single selection — should clear multi-cam preview when switching clips.
    let onSelectClip: (Clip) -> Void
    /// Opens multi-camera preview for the shared `cameraGroupId` (grid double-click).
    var onOpenMultiCamGroup: ((String) -> Void)?

    @State private var viewMode: ViewMode = .grid
    @State private var sortBy: SortOption = .dateCreated
    @State private var sortOrder: SortOrder = .descending
    @State private var searchText = ""
    @State private var filterStatus: ReviewStatus?
    @State private var showingFilterMenu = false
    @State private var isDropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    public var body: some View {
        VStack(spacing: 0) {
            ClipGridViewToolbar(
                viewMode: $viewMode,
                sortBy: $sortBy,
                sortOrder: $sortOrder,
                searchText: $searchText,
                filterStatus: $filterStatus,
                showingFilterMenu: $showingFilterMenu,
                clipCount: filteredClips.count,
                searchPrompt: searchPrompt,
                hasActiveFilters: hasActiveFilters,
                clearFilters: clearFilters
            )

            Divider()

            ClipProjectOverviewHeader(
                project: project,
                totalClipCount: clipStore.clips.count,
                visibleClipCount: sortedClips.count,
                reviewedClipCount: filteredClips.filter { $0.reviewStatus != .unreviewed }.count,
                proxyReadyCount: filteredClips.filter { [.ready, .completed].contains($0.proxyStatus) }.count,
                attentionCount: filteredClips.filter(Self.requiresAttention).count,
                activeSearchText: searchText,
                activeStatus: filterStatus,
                clearFilters: clearFilters
            )

            Divider()

            Group {
                if clipStore.loading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredClips.isEmpty {
                    EmptyStateView(
                        searchText: searchText,
                        filterStatus: filterStatus,
                        projectMode: project.mode
                    )
                } else if viewMode == .grid {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(sortedClips) { clip in
                                let multiCam = clip.cameraGroupId.map { clipStore.hasMultipleAngles(forGroupId: $0) } ?? false
                                ClipGridItemView(
                                    clip: clip,
                                    isSelected: selectedClip?.id == clip.id,
                                    hasMultiCam: multiCam,
                                    onSelect: { onSelectClip(clip) },
                                    onOpenMultiCam: { gid in onOpenMultiCamGroup?(gid) }
                                )
                            }
                        }
                        .padding()
                    }
                } else {
                    ClipListView(
                        clips: sortedClips,
                        selectedClip: $selectedClip,
                        clipStore: clipStore,
                        onSelectClip: onSelectClip,
                        onOpenMultiCamGroup: onOpenMultiCamGroup
                    )
                }
            }
        }
        .navigationTitle(project.name)
        .overlay {
            if isDropTargeted || isImportingMedia {
                ClipImportOverlay(
                    projectName: project.name,
                    isTargeted: isDropTargeted,
                    isImporting: isImportingMedia
                )
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var filteredClips: [Clip] {
        clipStore.clips.filter { clip in
            let matchesSearch = searchText.isEmpty || Self.searchableText(for: clip).localizedCaseInsensitiveContains(searchText)
            let matchesStatus = filterStatus == nil || clip.reviewStatus == filterStatus
            return matchesSearch && matchesStatus
        }
    }

    private var sortedClips: [Clip] {
        filteredClips.sorted { lhs, rhs in
            let isAscendingComparison: Bool
            switch sortBy {
            case .dateCreated:
                isAscendingComparison = lhs.ingestedAt < rhs.ingestedAt
            case .name:
                isAscendingComparison = URL(fileURLWithPath: lhs.sourcePath).lastPathComponent < URL(fileURLWithPath: rhs.sourcePath).lastPathComponent
            case .duration:
                isAscendingComparison = lhs.duration < rhs.duration
            case .status:
                isAscendingComparison = lhs.reviewStatus.rawValue < rhs.reviewStatus.rawValue
            }
            return sortOrder == .ascending ? isAscendingComparison : !isAscendingComparison
        }
    }

    private var hasActiveFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filterStatus != nil
    }

    private var searchPrompt: String {
        switch project.mode {
        case .narrative:
            return "Search clips, scenes, shots, takes..."
        case .documentary:
            return "Search clips, subjects, sessions, tags..."
        }
    }

    private func clearFilters() {
        searchText = ""
        filterStatus = nil
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let supportedProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !supportedProviders.isEmpty else {
            return false
        }

        loadDroppedURLs(from: supportedProviders)
        return true
    }

    private func loadDroppedURLs(from providers: [NSItemProvider]) {
        let collector = DroppedURLCollector()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                collector.append(url)
            }
        }

        group.notify(queue: .main) {
            let uniqueURLs = Dictionary(
                collector.urls.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
                uniquingKeysWith: { first, _ in first }
            )
            .values
            .sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }

            guard !uniqueURLs.isEmpty else {
                return
            }

            importDroppedURLs(uniqueURLs)
        }
    }

    private static func searchableText(for clip: Clip) -> String {
        var components: [String] = [
            URL(fileURLWithPath: clip.sourcePath).lastPathComponent,
            clip.sourceFormat.rawValue,
            clip.reviewStatus.displayName,
            clip.proxyStatus.rawValue,
            clip.syncResult.confidence.rawValue,
            clip.syncResult.method.rawValue
        ]

        if let narrative = clip.narrativeMeta {
            components.append(contentsOf: [
                narrative.sceneNumber,
                narrative.shotCode,
                String(narrative.takeNumber),
                narrative.cameraId,
                narrative.scriptPage ?? "",
                narrative.setUpDescription ?? "",
                narrative.director ?? "",
                narrative.dp ?? ""
            ])
        }

        if let documentary = clip.documentaryMeta {
            components.append(contentsOf: [
                documentary.subjectName,
                documentary.sessionLabel,
                documentary.location ?? "",
                documentary.topicTags.joined(separator: " "),
                String(documentary.shootingDay),
                documentary.interviewerOffscreen ? "interviewer offscreen" : ""
            ])
        }

        if let aiScores = clip.aiScores {
            components.append(aiScores.modelVersion)
            components.append(contentsOf: aiScores.reasoning.map(\.message))
        }

        return components.joined(separator: " ")
    }

    private static func requiresAttention(_ clip: Clip) -> Bool {
        clip.reviewStatus == .flagged
            || clip.reviewStatus == .x
            || clip.proxyStatus == .error
            || clip.syncResult.confidence == .manualRequired
    }
}

private struct ClipGridItemView: View {
    let clip: Clip
    let isSelected: Bool
    let hasMultiCam: Bool
    let onSelect: () -> Void
    let onOpenMultiCam: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(clip: clip)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                    )

                if hasMultiCam {
                    Text("Multi-Cam")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.88))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: clip.sourcePath).lastPathComponent)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let contextLabel = clipContextLabel {
                    Text(contextLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text(formatDuration(clip.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(clip.sourceFps, specifier: "%.2f") fps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    ReviewStatusBadge(status: clip.reviewStatus)
                    ProxyStatusBadge(status: clip.proxyStatus)
                    if clip.syncResult.confidence != .unsynced {
                        SyncStatusBadge(confidence: clip.syncResult.confidence)
                    }
                    if let composite = clip.aiScores?.composite {
                        AIScoreBadge(score: composite)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if hasMultiCam, let gid = clip.cameraGroupId {
                onOpenMultiCam(gid)
            }
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "00:00"
    }

    private var clipContextLabel: String? {
        if let narrative = clip.narrativeMeta {
            return "Scene \(narrative.sceneNumber) • \(narrative.shotCode) • Take \(narrative.takeNumber) • Cam \(narrative.cameraId)"
        }

        if let documentary = clip.documentaryMeta {
            return "\(documentary.subjectName) • Day \(documentary.shootingDay) • \(documentary.sessionLabel)"
        }

        return nil
    }
}

private struct ThumbnailView: View {
    let clip: Clip
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                VStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No Thumbnail")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .clipped()
        .onAppear(perform: loadThumbnail)
    }

    private func loadThumbnail() {
        guard let proxyPath = clip.proxyPath else {
            return
        }

        Task {
            do {
                let asset = AVAsset(url: URL(fileURLWithPath: proxyPath))
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 320, height: 180)
                let result = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
                await MainActor.run {
                    image = NSImage(cgImage: result.image, size: NSSize(width: 320, height: 180))
                }
            } catch {
                image = nil
            }
        }
    }
}

struct ReviewStatusBadge: View {
    let status: ReviewStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.18))
            .foregroundColor(status.color)
            .cornerRadius(4)
    }
}

struct ProxyStatusBadge: View {
    let status: ProxyStatus

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: status.iconName)
                .font(.system(size: 8))
            Text(status.rawValue.capitalized)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.18))
        .foregroundColor(status.color)
        .cornerRadius(4)
    }
}

struct SyncStatusBadge: View {
    let confidence: SyncConfidence

    var body: some View {
        Image(systemName: confidence == .manualRequired ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.system(size: 12))
            .foregroundColor(confidence == .manualRequired ? .red : .green)
    }
}

enum ViewMode: CaseIterable {
    case grid
    case list
}

enum SortOption: CaseIterable {
    case dateCreated
    case name
    case duration
    case status

    var displayName: String {
        switch self {
        case .dateCreated: return "Date Created"
        case .name: return "Name"
        case .duration: return "Duration"
        case .status: return "Status"
        }
    }
}

enum SortOrder {
    case ascending
    case descending
}

extension ReviewStatus {
    var displayName: String {
        switch self {
        case .unreviewed: return "Unreviewed"
        case .circled: return "Circled"
        case .flagged: return "Flagged"
        case .x: return "X"
        case .deprioritized: return "Deprioritized"
        }
    }

    var color: Color {
        switch self {
        case .unreviewed: return .gray
        case .circled: return .green
        case .flagged: return .yellow
        case .x: return .red
        case .deprioritized: return .blue
        }
    }
}

extension ProxyStatus {
    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .ready: return "checkmark.circle"
        case .uploading: return "arrow.up.circle"
        case .completed: return "checkmark.circle.fill"
        case .error: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .processing: return .blue
        case .ready: return .green
        case .uploading: return .orange
        case .completed: return .green
        case .error: return .red
        }
    }
}

private final class DroppedURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

private struct EmptyStateView: View {
    let searchText: String
    let filterStatus: ReviewStatus?
    let projectMode: ProjectMode

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty && filterStatus == nil ? "No Clips Yet" : "No Results Found")
                .font(.title2)
                .fontWeight(.medium)
            Text(searchText.isEmpty && filterStatus == nil
                 ? (projectMode == .narrative
                    ? "Drop takes here to import them instantly, or add a watch folder for ongoing ingest."
                    : "Drop footage here to import it instantly, or add a watch folder for ongoing ingest.")
                 : "Try adjusting your search or review-status filter.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipImportOverlay: View {
    let projectName: String
    let isTargeted: Bool
    let isImporting: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.12)

            VStack(spacing: 12) {
                Image(systemName: isImporting ? "arrow.triangle.2.circlepath.circle.fill" : "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isImporting)

                Text(isImporting ? "Importing Media…" : "Drop Media To Import")
                    .font(.title3.weight(.semibold))

                Text(
                    isImporting
                    ? "SLATE is importing the dropped media into \(projectName)."
                    : "Drop files or folders here to import them into \(projectName)."
                )
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [10, 8])
                    )
            )
            .padding(36)
        }
        .transition(.opacity)
    }
}

private struct ClipProjectOverviewHeader: View {
    let project: Project
    let totalClipCount: Int
    let visibleClipCount: Int
    let reviewedClipCount: Int
    let proxyReadyCount: Int
    let attentionCount: Int
    let activeSearchText: String
    let activeStatus: ReviewStatus?
    let clearFilters: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasActiveFilters {
                    Button("Clear Filters", action: clearFilters)
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }

            HStack(spacing: 12) {
                OverviewMetricCard(title: "Visible", value: "\(visibleClipCount)", tint: .accentColor)
                OverviewMetricCard(title: "Reviewed", value: "\(reviewedClipCount)", tint: .green)
                OverviewMetricCard(title: "Proxy Ready", value: "\(proxyReadyCount)", tint: .blue)
                OverviewMetricCard(title: "Attention", value: "\(attentionCount)", tint: attentionCount == 0 ? .secondary : .orange)
            }

            if hasActiveFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if !activeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ActiveFilterChip(label: "Search", value: activeSearchText)
                        }
                        if let activeStatus {
                            ActiveFilterChip(label: "Status", value: activeStatus.displayName)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var hasActiveFilters: Bool {
        !activeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || activeStatus != nil
    }

    private var summaryText: String {
        "\(project.mode.rawValue.capitalized) project • \(visibleClipCount) of \(max(totalClipCount, visibleClipCount)) clips in view"
    }
}

private struct OverviewMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct ActiveFilterChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct ClipListView: View {
    let clips: [Clip]
    @Binding var selectedClip: Clip?
    @ObservedObject var clipStore: GRDBClipStore
    let onSelectClip: (Clip) -> Void
    var onOpenMultiCamGroup: ((String) -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(clips) { clip in
                    let multiCam = clip.cameraGroupId.map { clipStore.hasMultipleAngles(forGroupId: $0) } ?? false
                    ClipListItemView(
                        clip: clip,
                        isSelected: selectedClip?.id == clip.id,
                        hasMultiCam: multiCam,
                        onSelect: { onSelectClip(clip) },
                        onOpenMultiCam: { gid in onOpenMultiCamGroup?(gid) }
                    )
                    Divider()
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct ClipListItemView: View {
    let clip: Clip
    let isSelected: Bool
    let hasMultiCam: Bool
    let onSelect: () -> Void
    let onOpenMultiCam: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(clip: clip)
                    .frame(width: 120, height: 68)
                    .cornerRadius(6)

                if hasMultiCam {
                    Text("MC")
                        .font(.system(size: 9, weight: .bold))
                        .padding(3)
                        .background(Color.purple.opacity(0.9))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                        .padding(3)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: clip.sourcePath).lastPathComponent)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let contextLabel = clipContextLabel {
                    Text(contextLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(formatDuration(clip.duration))
                    Text("•")
                    Text("\(clip.sourceFps, specifier: "%.2f") fps")
                    Text("•")
                    Text(clip.sourceFormat.rawValue)
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ReviewStatusBadge(status: clip.reviewStatus)
                    ProxyStatusBadge(status: clip.proxyStatus)
                    if let composite = clip.aiScores?.composite {
                        AIScoreBadge(score: composite)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.08) : .clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if hasMultiCam, let gid = clip.cameraGroupId {
                onOpenMultiCam(gid)
            }
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "00:00"
    }

    private var clipContextLabel: String? {
        if let narrative = clip.narrativeMeta {
            return "Scene \(narrative.sceneNumber) • \(narrative.shotCode) • Take \(narrative.takeNumber) • Cam \(narrative.cameraId)"
        }

        if let documentary = clip.documentaryMeta {
            return "\(documentary.subjectName) • Day \(documentary.shootingDay) • \(documentary.sessionLabel)"
        }

        return nil
    }
}
