// SLATE — MultiCamPreviewView
// Side-by-side proxy playback for multi-camera groups (A/B/C/D) with shared transport.

import AppKit
import AVFoundation
import Combine
import SwiftUI
import SLATECore
import SLATESharedTypes

// MARK: - Public view

public struct MultiCamPreviewView: View {
    public let groupId: String
    public let clips: [Clip]
    @ObservedObject public var clipStore: GRDBClipStore
    @ObservedObject public var syncManager: SyncManager
    public var onClose: () -> Void

    @EnvironmentObject private var supabaseManager: SupabaseManager

    @StateObject private var playback = MultiCamPlaybackController()
    @State private var displayGroups: [CameraGroupNavItem] = []
    @State private var annotationTarget: AnnotationTarget?
    @State private var annotationBody = ""
    @State private var annotationType: AnnotationType = .text

    private let assemblyEngine = AssemblyEngine()

    /// Live clips for this group (store is source of truth).
    private var resolvedClips: [Clip] {
        clipStore.clips(forGroupId: groupId)
    }

    public init(
        groupId: String,
        clips: [Clip],
        clipStore: GRDBClipStore,
        syncManager: SyncManager,
        onClose: @escaping () -> Void = {}
    ) {
        self.groupId = groupId
        self.clips = clips
        self._clipStore = ObservedObject(wrappedValue: clipStore)
        self._syncManager = ObservedObject(wrappedValue: syncManager)
        self.onClose = onClose
    }

    public var body: some View {
        let visible = Array(resolvedClips.prefix(4))
        let masterId = playback.masterClipId
        let project = clipStore.projects.first { $0.id == visible.first?.projectId }

        VStack(spacing: 0) {
            headerBar(project: project)

            if visible.isEmpty {
                ContentUnavailableView("No Angles", systemImage: "video.slash", description: Text("This camera group has no clips."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch playback.state {
                case .idle, .loading:
                    ProgressView("Loading proxies…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .proxyPending(let status):
                    Text("Proxy not ready (\(status.rawValue)). Multi-cam preview needs all proxies finished.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .error(let message):
                    Text(message)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(visible, id: \.id) { clip in
                                VideoPlayerCell(
                                    clip: clip,
                                    player: playback.player(for: clip.id),
                                    isCircled: clip.reviewStatus == .circled,
                                    isMaster: clip.id == masterId,
                                    displayTimecode: playback.displayTimecode(for: clip.id),
                                    onCircle: {
                                        Task {
                                            await clipStore.applyCircleInMultiCamGroup(
                                                selectedClipId: clip.id,
                                                groupId: groupId
                                            )
                                        }
                                    },
                                    onFlag: {
                                        Task {
                                            await clipStore.updateReviewStatus(clipId: clip.id, status: .flagged)
                                        }
                                    },
                                    onTapTimecode: {
                                        annotationBody = ""
                                        annotationType = .text
                                        annotationTarget = AnnotationTarget(clipId: clip.id)
                                    }
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)

                        transportBar(duration: playback.masterDuration)

                        HStack {
                            Button {
                                circleBestTake(project: project, visible: visible)
                            } label: {
                                Label("Circle Best", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                            .help("Automatically circle best take candidate")
                            .disabled(project?.mode != .narrative)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
        .task(id: groupId) {
            await refreshNavGroups()
            await playback.load(
                clips: visible,
                jwt: supabaseManager.accessToken
            )
        }
        .onChange(of: clipStore.clips.count) { _, _ in
            Task { await refreshNavGroups() }
        }
        .onDisappear {
            playback.teardown()
        }
        .sheet(item: $annotationTarget) { target in
            AnnotationPopoverSheet(
                clipId: target.clipId,
                annotationType: $annotationType,
                bodyText: $annotationBody,
                syncManager: syncManager,
                onDismiss: { annotationTarget = nil }
            )
        }
    }

    private func headerBar(project: Project?) -> some View {
        HStack {
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close multi-cam preview")

            Spacer()

            Text(navTitle(project: project))
                .font(.headline)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 16) {
                Button {
                    navigateGroup(delta: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canStepPrevious)
                .help("Previous multi-cam group")

                Button {
                    navigateGroup(delta: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canStepNext)
                .help("Next multi-cam group")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func navTitle(project: Project?) -> String {
        guard let first = resolvedClips.first else {
            return "Multi-Cam"
        }
        if let n = first.narrativeMeta {
            return "Scene \(n.sceneNumber) • \(n.shotCode) • Take \(n.takeNumber)"
        }
        return "Multi-Cam"
    }

    private func transportBar(duration: Double) -> some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .help("Play/Pause multi-cam")

                Text(playback.masterTimecodeDisplay)
                    .font(.caption.monospaced())
                    .frame(minWidth: 100, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playback.scrubProgress },
                        set: { playback.scrub(toProgress: $0) }
                    ),
                    in: 0...1
                )
                .disabled(duration <= 0)

                Text(smpteString(seconds: duration, fps: playback.masterFps))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 100, alignment: .trailing)
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }

    private func smpteString(seconds: Double, fps: Double) -> String {
        let safeFrameRate = fps > 0 ? fps : 24
        let totalFrames = Int((seconds * safeFrameRate).rounded())
        let framesPerSec = Int(safeFrameRate.rounded())
        let hh = totalFrames / (3600 * framesPerSec)
        let mm = (totalFrames % (3600 * framesPerSec)) / (60 * framesPerSec)
        let ss = (totalFrames % (60 * framesPerSec)) / framesPerSec
        let ff = totalFrames % framesPerSec
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }

    private func circleBestTake(project: Project?, visible: [Clip]) {
        guard project?.mode == .narrative,
              let best = assemblyEngine.selectBestClipForMultiCamGroup(visible) else {
            return
        }
        Task {
            await clipStore.applyCircleInMultiCamGroup(selectedClipId: best.id, groupId: groupId)
        }
    }

    // MARK: - Group navigation

    private var currentGroupIndex: Int? {
        displayGroups.firstIndex { $0.groupId == groupId }
    }

    private var canStepPrevious: Bool {
        guard let idx = currentGroupIndex else { return false }
        return idx > 0
    }

    private var canStepNext: Bool {
        guard let idx = currentGroupIndex else { return false }
        return idx + 1 < displayGroups.count
    }

    private func navigateGroup(delta: Int) {
        guard let idx = currentGroupIndex else { return }
        let next = idx + delta
        guard displayGroups.indices.contains(next) else { return }
        NotificationCenter.default.post(
            name: .multiCamNavigateToGroup,
            object: nil,
            userInfo: ["groupId": displayGroups[next].groupId]
        )
    }

    private func refreshNavGroups() async {
        var byGroup: [String: [Clip]] = [:]
        for clip in clipStore.clips {
            guard let gid = clip.cameraGroupId, !gid.isEmpty else { continue }
            byGroup[gid, default: []].append(clip)
        }
        let ids = byGroup.filter { $0.value.count >= 2 }.map(\.key)
        let items = ids.map { id -> CameraGroupNavItem in
            let cs = clipStore.clips(forGroupId: id)
            let sortKey = sceneShotSortKey(for: cs.first)
            return CameraGroupNavItem(groupId: id, sortKey: sortKey)
        }
        .sorted { lhs, rhs in
            if lhs.sortKey != rhs.sortKey {
                return lhs.sortKey.localizedCompare(rhs.sortKey) == .orderedAscending
            }
            return lhs.groupId < rhs.groupId
        }
        displayGroups = items
    }

    private func sceneShotSortKey(for clip: Clip?) -> String {
        guard let clip, let n = clip.narrativeMeta else {
            return ""
        }
        return "\(n.sceneNumber)|\(n.shotCode)|\(n.takeNumber)"
    }
}

// MARK: - Navigation notification

extension Notification.Name {
    static let multiCamNavigateToGroup = Notification.Name("multiCamNavigateToGroup")
}

private struct CameraGroupNavItem: Identifiable, Equatable {
    var id: String { groupId }
    let groupId: String
    let sortKey: String
}

private struct AnnotationTarget: Identifiable {
    let clipId: String
    var id: String { clipId }
}

// MARK: - Cell

private struct VideoPlayerCell: View {
    let clip: Clip
    let player: AVPlayer?
    let isCircled: Bool
    let isMaster: Bool
    let displayTimecode: String
    let onCircle: () -> Void
    let onFlag: () -> Void
    let onTapTimecode: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if let player {
                    AVPlayerLayerContainer(player: player)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(Color.black)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.9))
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .cornerRadius(8)
                }

                Text(cameraLabel)
                    .font(.caption.bold())
                    .padding(6)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCircled ? Color.green.opacity(0.9) : Color.clear, lineWidth: 3)
            )

            HStack {
                if let composite = clip.aiScores?.composite {
                    AIScoreBadge(score: composite)
                }
                Spacer()
                Button(action: onCircle) {
                    Text("⭕")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Circle take")

                Button(action: onFlag) {
                    Image(systemName: "flag")
                }
                .buttonStyle(.borderless)
                .help("Flag")
            }

            Button(action: onTapTimecode) {
                Text(displayTimecode)
                    .font(.caption.monospaced())
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("Add annotation at this timecode")
        }
    }

    private var cameraLabel: String {
        let angle = clip.cameraAngle?.uppercased() ?? "?"
        return "\(angle)-CAM"
    }
}

// MARK: - AVPlayerLayer host

private struct AVPlayerLayerContainer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerHostingView {
        let v = AVPlayerHostingView()
        v.playerLayer.player = player
        return v
    }

    func updateNSView(_ nsView: AVPlayerHostingView, context: Context) {
        nsView.playerLayer.player = player
    }
}

private final class AVPlayerHostingView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

// MARK: - Annotation sheet (matches ClipDetailView flow)

private struct AnnotationPopoverSheet: View {
    let clipId: String
    @Binding var annotationType: AnnotationType
    @Binding var bodyText: String
    @ObservedObject var syncManager: SyncManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Annotation")
                .font(.headline)

            Picker("Type", selection: $annotationType) {
                ForEach(AnnotationType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.iconName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $bodyText)
                .frame(minHeight: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    let annotation = Annotation(
                        userId: "local-user",
                        userDisplayName: "Current User",
                        timecodeIn: "00:00:00:00",
                        body: bodyText,
                        type: annotationType
                    )
                    Task {
                        try? await syncManager.addAnnotation(to: clipId, annotation: annotation)
                        onDismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 280)
    }
}

// MARK: - Playback controller

@MainActor
private final class MultiCamPlaybackController: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case proxyPending(ProxyStatus)
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published var masterTimecodeDisplay = "00:00:00:00"
    @Published var scrubProgress: Double = 0
    @Published var isPlaying = false
    @Published private(set) var masterDuration: Double = 0
    @Published private(set) var masterFps: Double = 24

    private(set) var masterClipId: String?

    private var playersByClipId: [String: AVPlayer] = [:]
    private var clipById: [String: Clip] = [:]
    private var masterPlayer: AVPlayer?
    private var timeObserver: Any?
    private var rateObservation: NSKeyValueObservation?

    func player(for clipId: String) -> AVPlayer? {
        playersByClipId[clipId]
    }

    func displayTimecode(for clipId: String) -> String {
        guard let clip = clipById[clipId],
              let player = playersByClipId[clipId] else {
            return "00:00:00:00"
        }
        let fps = max(clip.sourceFps, 1)
        let master = masterClipId.flatMap { clipById[$0] }
        let masterOffset = Int64(master?.syncResult.offsetFrames ?? 0)
        let clipOffset = Int64(clip.syncResult.offsetFrames)
        let deltaFrames = clipOffset - masterOffset
        let t = player.currentTime().seconds
        let alignedSeconds = t - Double(deltaFrames) / fps
        return Self.smpte(seconds: alignedSeconds, fps: fps)
    }

    func load(clips: [Clip], jwt: String?) async {
        teardown()
        guard !clips.isEmpty else {
            state = .error("No clips to load.")
            return
        }

        guard clips.allSatisfy({ $0.proxyStatus == .ready }) else {
            state = .proxyPending(clips.first { $0.proxyStatus != .ready }?.proxyStatus ?? .pending)
            return
        }

        state = .loading

        let masterClip = clips.first { $0.cameraAngle?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "A" } ?? clips[0]
        masterClipId = masterClip.id
        masterFps = max(masterClip.sourceFps, 1)

        do {
            for clip in clips {
                let url = try await resolveURL(for: clip, jwt: jwt)
                let player = AVPlayer(url: url)
                playersByClipId[clip.id] = player
                clipById[clip.id] = clip
                if clip.id == masterClipId {
                    masterPlayer = player
                }
            }
        } catch {
            state = .error(error.localizedDescription)
            return
        }

        guard let masterPlayer else {
            state = .error("Missing master player.")
            return
        }

        masterDuration = await Self.loadDuration(for: masterPlayer)
        observeMaster(player: masterPlayer)
        wireRateSync(master: masterPlayer)
        await seekAllToInitialPositions(masterPlayer: masterPlayer)

        state = .ready
    }

    func togglePlayPause() {
        guard let master = masterPlayer else { return }
        if master.rate > 0.01 {
            master.pause()
        } else {
            master.play()
        }
    }

    func scrub(toProgress progress: Double) {
        guard let master = masterPlayer, masterDuration > 0 else { return }
        let t = progress * masterDuration
        let fps = max(masterFps, 1)
        master.seek(to: CMTime(seconds: t, preferredTimescale: CMTimeScale(fps.rounded())), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.syncFollowersToMasterExact()
            }
        }
    }

    func teardown() {
        if let token = timeObserver, let master = masterPlayer {
            master.removeTimeObserver(token)
        }
        timeObserver = nil
        rateObservation?.invalidate()
        rateObservation = nil

        for (_, player) in playersByClipId {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        playersByClipId.removeAll()
        clipById.removeAll()
        masterPlayer = nil
        masterClipId = nil
        masterDuration = 0
        isPlaying = false
        state = .idle
    }

    private func observeMaster(player: AVPlayer) {
        let fps = max(masterFps, 1)
        let interval = CMTime(value: 1, timescale: max(1, CMTimeScale(fps.rounded())))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.masterTimecodeDisplay = Self.smpte(seconds: time.seconds, fps: fps)
                if self.masterDuration > 0 {
                    self.scrubProgress = time.seconds / self.masterDuration
                }
                self.syncFollowersIfDrifted(masterTime: time.seconds)
            }
        }
    }

    private func wireRateSync(master: AVPlayer) {
        rateObservation = master.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            Task { @MainActor in
                let rate = player.rate
                self.isPlaying = rate > 0.01
                for (id, pl) in self.playersByClipId where id != self.masterClipId {
                    pl.rate = rate
                }
            }
        }
    }

    private func seekAllToInitialPositions(masterPlayer: AVPlayer) async {
        guard let mid = masterClipId, let masterClip = clipById[mid] else { return }
        let masterOffsetFrames = Int64(masterClip.syncResult.offsetFrames)
        let fps = max(masterFps, 1)

        for (clipId, player) in playersByClipId {
            guard let clip = clipById[clipId] else { continue }
            let clipOffsetFrames = Int64(clip.syncResult.offsetFrames)
            let delta = clipOffsetFrames - masterOffsetFrames
            let seconds = Double(delta) / fps
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                    cont.resume()
                }
            }
        }

        masterPlayer.pause()
        syncFollowersToMasterExact()
    }

    private func syncFollowersToMasterExact() {
        guard let mid = masterClipId,
              let master = masterPlayer,
              let masterClip = clipById[mid] else { return }
        let masterOffset = Int64(masterClip.syncResult.offsetFrames)
        let fps = max(masterFps, 1)
        let masterT = master.currentTime().seconds

        for (id, player) in playersByClipId where id != mid {
            guard let slave = clipById[id] else { continue }
            let delta = Int64(slave.syncResult.offsetFrames) - masterOffset
            let target = masterT + Double(delta) / fps
            let cm = CMTime(seconds: target, preferredTimescale: 600)
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func syncFollowersIfDrifted(masterTime: Double) {
        guard let mid = masterClipId,
              let masterClip = clipById[mid] else { return }
        let masterOffset = Int64(masterClip.syncResult.offsetFrames)
        let fps = max(masterFps, 1)

        for (id, player) in playersByClipId where id != mid {
            guard let slave = clipById[id] else { continue }
            let delta = Int64(slave.syncResult.offsetFrames) - masterOffset
            let expected = masterTime + Double(delta) / fps
            if abs(player.currentTime().seconds - expected) > 0.12 {
                let cm = CMTime(seconds: expected, preferredTimescale: 600)
                player.seek(to: cm, toleranceBefore: CMTime(seconds: 0.04, preferredTimescale: 600), toleranceAfter: CMTime(seconds: 0.04, preferredTimescale: 600))
            }
        }
    }

    private func resolveURL(for clip: Clip, jwt: String?) async throws -> URL {
        if let localPath = clip.proxyPath, FileManager.default.fileExists(atPath: localPath) {
            return URL(fileURLWithPath: localPath)
        }
        let resolvedJWT = jwt
            ?? ProcessInfo.processInfo.environment["SLATE_DEBUG_JWT"]
            ?? ""
        let signed = try await ShareLinkService.shared.signProxyURL(
            clipId: clip.id,
            auth: .jwt(resolvedJWT)
        )
        guard let remoteURL = URL(string: signed.signedUrl) else {
            throw URLError(.badURL)
        }
        return remoteURL
    }

    private static func loadDuration(for player: AVPlayer) async -> Double {
        guard let asset = player.currentItem?.asset else {
            return 0
        }
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds >= 0 else { return 0 }
            return seconds
        } catch {
            return 0
        }
    }

    private static func smpte(seconds: Double, fps: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00:00" }
        let totalFrames = Int((seconds * fps).rounded())
        let framesPerSec = Int(fps.rounded())
        let hh = totalFrames / (3600 * framesPerSec)
        let mm = (totalFrames % (3600 * framesPerSec)) / (60 * framesPerSec)
        let ss = (totalFrames % (60 * framesPerSec)) / framesPerSec
        let ff = totalFrames % framesPerSec
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }
}
