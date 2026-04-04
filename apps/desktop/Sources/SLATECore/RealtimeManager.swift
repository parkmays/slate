// SLATE — RealtimeManager
// Owned by: Claude Code
//
// C4: Supabase Realtime subscription manager for the desktop app.
//
// Subscribes to channels defined in contracts/realtime-events.json and bridges
// incoming broadcast events to NotificationCenter so existing views react
// without knowing Supabase directly:
//
//   clip:{clipId} channel
//     annotation_added      → .annotationAdded
//     annotation_resolved   → .annotationUpdated
//     review_status_changed → .clipUpdated
//     proxy_status_changed  → .clipUpdated
//     ai_scores_ready       → .clipUpdated
//     sync_result_updated   → .clipUpdated
//
//   project:{projectId} channel
//     clip_ingested         → .realtimeClipIngested
//     clip_proxy_ready      → .realtimeClipProxyReady
//
// Offline-first: when client == nil all calls are no-ops.

import Foundation
import Supabase

// MARK: - Extra notification names (C4)

extension Notification.Name {
    /// A new clip was ingested and written to the database (project-level broadcast).
    public static let realtimeClipIngested   = Notification.Name("realtimeClipIngested")
    /// Proxy generation completed for a clip (project-level broadcast).
    public static let realtimeClipProxyReady = Notification.Name("realtimeClipProxyReady")
}

// MARK: - RealtimeManager

@MainActor
public final class RealtimeManager {

    // MARK: - Private state

    private let client: SupabaseClient?

    private var projectChannel: RealtimeChannelV2?
    private var clipChannel: RealtimeChannelV2?

    private var projectTask: Task<Void, Never>?
    private var clipTask: Task<Void, Never>?

    private var subscribedProjectId: String?
    private var subscribedClipId: String?

    // MARK: - Init

    public init(client: SupabaseClient?) {
        self.client = client
    }

    // MARK: - Project channel

    /// Subscribes to `project:{projectId}`. Safe to call when already subscribed
    /// to the same project — does nothing in that case.
    public func subscribeToProject(_ projectId: String) async {
        guard let client else { return }
        guard projectId != subscribedProjectId else { return }

        await unsubscribeFromProject()
        subscribedProjectId = projectId

        let channel = client.realtimeV2.channel("project:\(projectId)")
        projectChannel = channel

        // Capture streams before subscribe() to guarantee no events are missed.
        let ingestedStream   = channel.broadcastStream(event: "clip_ingested")
        let proxyReadyStream = channel.broadcastStream(event: "clip_proxy_ready")

        projectTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await payload in ingestedStream {
                        await self?.postProjectNotification(.realtimeClipIngested, payload: payload)
                    }
                }
                group.addTask {
                    for await payload in proxyReadyStream {
                        await self?.postProjectNotification(.realtimeClipProxyReady, payload: payload)
                    }
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            // Swallow error for offline-first; optionally log
        }
    }

    public func unsubscribeFromProject() async {
        projectTask?.cancel()
        projectTask = nil
        if let channel = projectChannel, let client {
            await client.realtimeV2.removeChannel(channel)
        }
        projectChannel     = nil
        subscribedProjectId = nil
    }

    // MARK: - Clip channel

    /// Subscribes to `clip:{clipId}`. Safe to call when already subscribed to the
    /// same clip — does nothing in that case.
    public func subscribeToClip(_ clipId: String) async {
        guard let client else { return }
        guard clipId != subscribedClipId else { return }

        await unsubscribeFromClip()
        subscribedClipId = clipId

        let channel = client.realtimeV2.channel("clip:\(clipId)")
        clipChannel = channel

        // Capture all event streams before subscribing.
        let annotationAddedStream    = channel.broadcastStream(event: "annotation_added")
        let annotationResolvedStream = channel.broadcastStream(event: "annotation_resolved")
        let reviewChangedStream      = channel.broadcastStream(event: "review_status_changed")
        let proxyChangedStream       = channel.broadcastStream(event: "proxy_status_changed")
        let aiScoresStream           = channel.broadcastStream(event: "ai_scores_ready")
        let syncResultStream         = channel.broadcastStream(event: "sync_result_updated")

        clipTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await payload in annotationAddedStream {
                        await self?.postClipNotification(.annotationAdded, clipId: clipId, payload: payload)
                    }
                }
                group.addTask {
                    for await payload in annotationResolvedStream {
                        await self?.postClipNotification(.annotationUpdated, clipId: clipId, payload: payload)
                    }
                }
                group.addTask {
                    for await _ in reviewChangedStream {
                        await self?.postClipNotification(.clipUpdated, clipId: clipId, payload: [:])
                    }
                }
                group.addTask {
                    for await _ in proxyChangedStream {
                        await self?.postClipNotification(.clipUpdated, clipId: clipId, payload: [:])
                    }
                }
                group.addTask {
                    for await _ in aiScoresStream {
                        await self?.postClipNotification(.clipUpdated, clipId: clipId, payload: [:])
                    }
                }
                group.addTask {
                    for await _ in syncResultStream {
                        await self?.postClipNotification(.clipUpdated, clipId: clipId, payload: [:])
                    }
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            // Swallow error for offline-first; optionally log
        }
    }

    public func unsubscribeFromClip() async {
        clipTask?.cancel()
        clipTask = nil
        if let channel = clipChannel, let client {
            await client.realtimeV2.removeChannel(channel)
        }
        clipChannel     = nil
        subscribedClipId = nil
    }

    // MARK: - Teardown

    /// Unsubscribes from all channels. Called on sign-out.
    public func unsubscribeAll() async {
        await unsubscribeFromProject()
        await unsubscribeFromClip()
    }

    // MARK: - Private helpers

    private func postProjectNotification(_ name: Notification.Name,
                                         payload: JSONObject) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: ["payload": payload as AnyObject]
        )
    }

    private func postClipNotification(_ name: Notification.Name,
                                      clipId: String,
                                      payload: JSONObject) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: ["clipId": clipId, "payload": payload as AnyObject]
        )
    }
}

