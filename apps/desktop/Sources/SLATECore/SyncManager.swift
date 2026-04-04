// SLATE — SyncManager
// Owned by: Claude Code
//
// Desktop-side coordination for annotations and local realtime-style
// notifications. C2 uses the canonical shared Annotation model rather than a
// separate GRDB annotation schema.

import Foundation
import Supabase
import SwiftUI
import SLATESharedTypes

@MainActor
public final class SyncManager: ObservableObject {
    @Published public var isConnected = true
    @Published public var annotationsByClipId: [String: [Annotation]] = [:]
    @Published public var connectionError: Error?

    private let supabase: SupabaseClient?

    public init(supabase: SupabaseClient? = nil) {
        self.supabase = supabase
    }

    public func primeAnnotations(_ annotations: [Annotation], forClipId clipId: String) {
        annotationsByClipId[clipId] = annotations
    }

    public func getAnnotations(forClipId clipId: String, fallback: [Annotation] = []) -> [Annotation] {
        annotationsByClipId[clipId] ?? fallback
    }

    public func addAnnotation(to clipId: String, annotation: Annotation) async throws {
        annotationsByClipId[clipId, default: []].append(annotation)
        NotificationCenter.default.post(
            name: .annotationAdded,
            object: annotation,
            userInfo: ["clipId": clipId]
        )
    }

    public func updateAnnotation(for clipId: String, annotation: Annotation) async throws {
        guard var annotations = annotationsByClipId[clipId],
              let index = annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return
        }

        annotations[index] = annotation
        annotationsByClipId[clipId] = annotations
        NotificationCenter.default.post(
            name: .annotationUpdated,
            object: annotation,
            userInfo: ["clipId": clipId]
        )
    }

    public func deleteAnnotation(for clipId: String, annotationId: String) async throws {
        annotationsByClipId[clipId]?.removeAll { $0.id == annotationId }
        NotificationCenter.default.post(
            name: .annotationDeleted,
            object: nil,
            userInfo: ["clipId": clipId, "annotationId": annotationId]
        )
    }
}

extension Notification.Name {
    public static let annotationAdded = Notification.Name("annotationAdded")
    public static let annotationUpdated = Notification.Name("annotationUpdated")
    public static let annotationDeleted = Notification.Name("annotationDeleted")
    public static let clipUpdated = Notification.Name("clipUpdated")
    public static let ingestProgressUpdated = Notification.Name("ingestProgressUpdated")
    public static let watchFoldersUpdated = Notification.Name("watchFoldersUpdated")
}

extension AnnotationType {
    public var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .voice:
            return "Voice"
        }
    }

    public var iconName: String {
        switch self {
        case .text:
            return "bubble.left.fill"
        case .voice:
            return "waveform"
        }
    }
}
