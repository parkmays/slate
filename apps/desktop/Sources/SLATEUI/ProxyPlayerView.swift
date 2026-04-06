// SLATE — ProxyPlayerView
// Owned by: Claude Code
//
// C3: AVPlayer-based proxy video player. Resolution priority:
//   1. Local proxy file at clip.proxyPath (offline-first, fastest)
//   2. Presigned Cloudflare R2 URL via sign-proxy-url edge function (online)
//   3. Graceful placeholder when proxy is not yet ready
//
// The player is embedded as a tab in ClipDetailView ("Preview").
// Timecode display reads from AVPlayer's currentTime and the clip's source FPS.
//
// C4: Reads the live Supabase Auth JWT from SupabaseManager via @EnvironmentObject
// so sign-proxy-url receives a real bearer token instead of a placeholder.

import AVKit
import SwiftUI
import SLATECore
import SLATESharedTypes

// MARK: - Public view

public struct ProxyPlayerView: View {
    let clip: Clip

    @StateObject private var controller = ProxyPlayerController()
    /// Injected by the view hierarchy (SLATEApp → ContentView → ClipDetailView).
    /// Provides the live Supabase Auth JWT for presigned-URL requests.
    @EnvironmentObject private var supabaseManager: SupabaseManager

    public init(clip: Clip) {
        self.clip = clip
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch controller.state {
            case .idle:
                Color.black

            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .colorScheme(.dark)
                    Text("Loading proxy…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

            case .ready(let player):
                ProxyVideoStack(clip: clip, player: player, timecode: $controller.displayTimecode)

            case .proxyPending(let status):
                ProxyPendingView(status: status)

            case .error(let message):
                // Capture the token at the time the retry button is pressed.
                let jwt = supabaseManager.accessToken
                ProxyErrorView(message: message) {
                    Task { await controller.load(clip: clip, jwt: jwt) }
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .cornerRadius(8)
        .task {
            await controller.load(clip: clip, jwt: supabaseManager.accessToken)
        }
        .onChange(of: clip.id) {
            let jwt = supabaseManager.accessToken
            Task { await controller.load(clip: clip, jwt: jwt) }
        }
        .onDisappear {
            controller.pause()
        }
    }
}

// MARK: - Video stack (player + timecode bar)

private struct ProxyVideoStack: View {
    let clip: Clip
    let player: AVPlayer
    @Binding var timecode: String

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .onAppear { player.play() }

            // Timecode / duration bar
            HStack {
                Text(timecode)
                    .font(.caption.monospaced())
                    .foregroundColor(.white)
                Spacer()
                Text(smpteString(seconds: clip.duration, fps: clip.sourceFps))
                    .font(.caption.monospaced())
                    .foregroundColor(Color.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.85))
        }
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
}

// MARK: - Pending placeholder

private struct ProxyPendingView: View {
    let status: ProxyStatus

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: pendingIcon)
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(pendingTitle)
                .font(.headline)
                .foregroundColor(.white)
            Text(subtitleText)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var subtitleText: String {
        switch status {
        case .pending:    return "Proxy generation is queued. It will start after ingest completes."
        case .processing: return "VideoToolbox is transcoding the proxy. This may take a few minutes."
        case .uploading:  return "Uploading proxy to cloud storage for remote review."
        case .error:      return "Proxy generation encountered an error. Check ingest progress."
        case .ready:      return "" // Should never show this view for .ready
        case .completed:  return "" // Same as ready when shown (should not appear for playable state)
        }
    }

    private var pendingIcon: String {
        switch status {
        case .processing: return "gear"
        case .uploading: return "arrow.up.circle"
        default: return "clock"
        }
    }

    private var pendingTitle: String {
        switch status {
        case .processing: return "Generating Proxy…"
        case .uploading: return "Uploading Proxy…"
        default: return "Proxy Not Ready"
        }
    }
}

// MARK: - Error view

private struct ProxyErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Could Not Load Proxy")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Controller

@MainActor
final class ProxyPlayerController: ObservableObject {

    enum PlayerState {
        case idle
        case loading
        case ready(AVPlayer)
        case proxyPending(ProxyStatus)
        case error(String)
    }

    @Published var state: PlayerState = .idle
    @Published var displayTimecode: String = "00:00:00:00"

    private var timeObserverToken: Any?
    private weak var currentPlayer: AVPlayer?

    /// Loads the proxy for `clip`, authenticating presigned-URL requests with
    /// `jwt` when provided.  Falls back to `SLATE_DEBUG_JWT` for local testing,
    /// then to an empty string (which will surface a 401 from the edge function
    /// rather than a crash).
    func load(clip: Clip, jwt: String? = nil) async {
        // Stop and clear any existing player
        teardownPlayer()
        state = .loading

        // Guard: proxy must be ready before we can play
        guard [.ready, .completed].contains(clip.proxyStatus) else {
            state = .proxyPending(clip.proxyStatus)
            return
        }

        // 1 — try local proxy path first (offline-first)
        if let localPath = clip.proxyPath {
            let fileURL = URL(fileURLWithPath: localPath)
            if FileManager.default.fileExists(atPath: localPath) {
                setupPlayer(url: fileURL, fps: clip.sourceFps)
                return
            }
        }

        // 2 — request a presigned R2 URL using the live session token (C4).
        let resolvedJWT = jwt
            ?? ProcessInfo.processInfo.environment["SLATE_DEBUG_JWT"]
            ?? ""

        do {
            let signed = try await ShareLinkService.shared.signProxyURL(
                clipId: clip.id,
                auth: .jwt(resolvedJWT)
            )
            guard let remoteURL = URL(string: signed.signedUrl) else {
                state = .error("Server returned an invalid URL.")
                return
            }
            setupPlayer(url: remoteURL, fps: clip.sourceFps)
        } catch ShareLinkError.notConfigured {
            // Supabase not yet configured — degrade gracefully rather than crashing.
            state = .error(
                "Remote proxy streaming requires SLATE_SUPABASE_URL to be set.\n" +
                "Locally transcoded proxies play without Supabase."
            )
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func pause() {
        currentPlayer?.pause()
    }

    // MARK: - Private

    private func setupPlayer(url: URL, fps: Double) {
        let player = AVPlayer(url: url)
        currentPlayer = player

        // Periodic timecode observer at every frame
        let interval = CMTime(value: 1, timescale: max(1, CMTimeScale(fps.rounded())))
        let safeFrameRate = fps > 0 ? fps : 24

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.displayTimecode = Self.smpteString(
                    seconds: time.seconds,
                    fps: safeFrameRate
                )
            }
        }

        state = .ready(player)
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let player = currentPlayer {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        currentPlayer?.pause()
        currentPlayer = nil
    }

    nonisolated private static func smpteString(seconds: Double, fps: Double) -> String {
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
