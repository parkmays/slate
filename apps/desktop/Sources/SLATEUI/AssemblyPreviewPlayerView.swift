import AVKit
import SwiftUI
import SLATESharedTypes

struct AssemblyPreviewPlayerView: View {
    let assembly: Assembly
    let clipsById: [String: Clip]

    @StateObject private var controller = AssemblyPreviewPlayerController()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                switch controller.state {
                case .idle, .loading:
                    ProgressView("Building preview…")
                        .tint(.white)
                case .empty:
                    VStack(spacing: 12) {
                        Image(systemName: "film.stack")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text("No playable proxy clips in this assembly.")
                            .foregroundColor(.white)
                    }
                case .error(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.orange)
                        Text(message)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                case .ready(let player, _, _):
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)

            if case .ready(_, let segments, let duration) = controller.state {
                VStack(spacing: 8) {
                    AssemblyMarkerBar(
                        segments: segments,
                        duration: duration,
                        currentTime: controller.currentSeconds
                    )
                    HStack {
                        Text(controller.currentTimecode)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(activeLabel(for: segments, currentTime: controller.currentSeconds) ?? assembly.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .cornerRadius(10)
        .task {
            await controller.load(assembly: assembly, clipsById: clipsById)
        }
        .onChange(of: assembly.clips) {
            Task { await controller.load(assembly: assembly, clipsById: clipsById) }
        }
    }

    private func activeLabel(for segments: [AssemblyPreviewSegment], currentTime: Double) -> String? {
        segments.first(where: { currentTime >= $0.startTime && currentTime < $0.startTime + $0.duration })?.label
    }
}

private struct AssemblyMarkerBar: View {
    let segments: [AssemblyPreviewSegment]
    let duration: Double
    let currentTime: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)

                Capsule()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: geometry.size.width * max(0, min(currentTime / max(duration, 0.001), 1)), height: 8)

                ForEach(segments) { segment in
                    let x = geometry.size.width * CGFloat(segment.startTime / max(duration, 0.001))
                    Rectangle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 2, height: 14)
                        .offset(x: x)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 14)
    }
}

private struct AssemblyPreviewSegment: Identifiable {
    let id = UUID()
    let clipId: String
    let label: String
    let startTime: Double
    let duration: Double
}

@MainActor
private final class AssemblyPreviewPlayerController: ObservableObject {
    enum PreviewState {
        case idle
        case loading
        case ready(AVPlayer, [AssemblyPreviewSegment], Double)
        case empty
        case error(String)
    }

    @Published var state: PreviewState = .idle
    @Published var currentTimecode = "00:00:00:00"
    @Published var currentSeconds: Double = 0

    private weak var player: AVPlayer?
    private var timeObserverToken: Any?

    func load(assembly: Assembly, clipsById: [String: Clip]) async {
        teardown()
        state = .loading

        do {
            let preview = try await buildPreview(assembly: assembly, clipsById: clipsById)
            guard !preview.segments.isEmpty else {
                state = .empty
                return
            }

            let player = AVPlayer(playerItem: AVPlayerItem(asset: preview.composition))
            self.player = player
            installObserver(on: player, fps: preview.fps)
            state = .ready(player, preview.segments, preview.duration)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func installObserver(on player: AVPlayer, fps: Double) {
        let frameRate = max(fps.rounded(), 1)
        let interval = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentSeconds = time.seconds
                self.currentTimecode = Self.smpteString(seconds: time.seconds, fps: frameRate)
            }
        }
    }

    private func buildPreview(
        assembly: Assembly,
        clipsById: [String: Clip]
    ) async throws -> (composition: AVMutableComposition, segments: [AssemblyPreviewSegment], duration: Double, fps: Double) {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return (composition, [], 0, 24)
        }

        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var segments: [AssemblyPreviewSegment] = []
        var cursor = CMTime.zero
        var previewFPS = 24.0

        for assemblyClip in assembly.clips {
            guard let clip = clipsById[assemblyClip.clipId],
                  let mediaURL = playableURL(for: clip) else {
                continue
            }

            let asset = AVAsset(url: mediaURL)
            let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = sourceVideoTracks.first else {
                continue
            }

            let sourceFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)
            previewFPS = sourceFrameRate > 0 ? Double(sourceFrameRate) : clip.sourceFps
            let start = CMTime(seconds: assemblyClip.inPoint, preferredTimescale: 600)
            let duration = CMTime(seconds: max(assemblyClip.outPoint - assemblyClip.inPoint, 0), preferredTimescale: 600)
            let timeRange = CMTimeRange(start: start, duration: duration)

            try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: cursor)
            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = sourceAudioTracks.first {
                try audioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: cursor)
            }

            segments.append(
                AssemblyPreviewSegment(
                    clipId: assemblyClip.clipId,
                    label: assemblyClip.sceneLabel,
                    startTime: cursor.seconds,
                    duration: duration.seconds
                )
            )
            cursor = cursor + duration
        }

        return (composition, segments, cursor.seconds, previewFPS)
    }

    private func playableURL(for clip: Clip) -> URL? {
        if let proxyPath = clip.proxyPath, FileManager.default.fileExists(atPath: proxyPath) {
            return URL(fileURLWithPath: proxyPath)
        }
        if FileManager.default.fileExists(atPath: clip.sourcePath) {
            return URL(fileURLWithPath: clip.sourcePath)
        }
        return nil
    }

    private func teardown() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        player?.pause()
        player = nil
        currentSeconds = 0
        currentTimecode = "00:00:00:00"
    }

    nonisolated private static func smpteString(seconds: Double, fps: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00:00" }
        let safeFPS = max(fps, 1)
        let totalFrames = Int((seconds * safeFPS).rounded())
        let framesPerSecond = Int(safeFPS.rounded())
        let hh = totalFrames / (framesPerSecond * 3600)
        let mm = (totalFrames / (framesPerSecond * 60)) % 60
        let ss = (totalFrames / framesPerSecond) % 60
        let ff = totalFrames % framesPerSecond
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }
}
