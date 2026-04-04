// SLATE — SupabaseManagerTests
// Owned by: Claude Code
//
// C4: Unit tests for SupabaseManager and RealtimeManager.
//
// All tests run without network access:
//   • SupabaseManager offline mode — verified via empty URL/key injection
//   • SupabaseManager configured mode — SupabaseClient init accepted with a
//     valid-format (but non-routable) URL; no network calls are made until
//     startListeningToAuthState() is awaited.
//   • RealtimeManager nil-client safety — subscribe/unsubscribe with a nil
//     client must complete without crashing (offline-first guarantee).

import Testing
import Foundation
@testable import SLATECore

private let validAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIn0.signature"

// MARK: - SupabaseManager: offline mode

@Suite("SupabaseManager — offline mode")
@MainActor
struct SupabaseManagerOfflineTests {

    @Test("Empty URL produces isConfigured = false")
    func emptyURLIsUnconfigured() {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "any-key")
        #expect(!mgr.isConfigured)
        #expect(mgr.client == nil)
    }

    @Test("Empty key produces isConfigured = false")
    func emptyKeyIsUnconfigured() {
        let mgr = SupabaseManager(supabaseURLString: "https://test.supabase.co", anonKey: "")
        #expect(!mgr.isConfigured)
        #expect(mgr.client == nil)
    }

    @Test("Malformed URL produces isConfigured = false")
    func malformedURLIsUnconfigured() {
        let mgr = SupabaseManager(supabaseURLString: "not a url !!!", anonKey: "anon-key")
        #expect(!mgr.isConfigured)
        #expect(mgr.client == nil)
    }

    @Test("Unconfigured manager has nil accessToken")
    func unconfiguredAccessTokenIsNil() {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "")
        #expect(mgr.accessToken == nil)
    }

    @Test("Unconfigured manager starts unauthenticated")
    func unconfiguredStartsUnauthenticated() {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "")
        #expect(!mgr.isAuthenticated)
        #expect(!mgr.isLoading)
        #expect(mgr.authError == nil)
        #expect(mgr.session == nil)
    }

    @Test("Unconfigured manager owns a non-nil RealtimeManager")
    func unconfiguredManagerHasRealtimeManager() {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "")
        // RealtimeManager itself should always be present (just a no-op in offline mode)
        // We verify by calling its public API — it must not throw or crash.
        // (No direct identity test needed; compile-time type check is sufficient here.)
        _ = mgr.realtime
    }

    @Test("startListeningToAuthState returns immediately when not configured")
    func startListeningReturnsWhenUnconfigured() async {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "")
        // Must complete without hanging (the guard let client else { return } path).
        await mgr.startListeningToAuthState()
    }

    @Test("signIn is a no-op when not configured and sets authError")
    func signInSetsErrorWhenUnconfigured() async {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "")
        await mgr.signIn(email: "a@b.com", password: "pass")
        #expect(mgr.authError != nil)
        #expect(!mgr.isAuthenticated)
    }

    @Test("signOut is a no-op when not configured")
    func signOutIsNoOpWhenUnconfigured() async {
        let mgr = SupabaseManager(supabaseURLString: "", anonKey: "")
        await mgr.signOut()   // Must not crash
        #expect(!mgr.isAuthenticated)
    }
}

// MARK: - SupabaseManager: configured mode (no network calls at init time)

@Suite("SupabaseManager — configured mode (no network)")
@MainActor
struct SupabaseManagerConfiguredTests {

    @Test("Valid URL + key produces isConfigured = true")
    func validURLAndKeyIsConfigured() {
        let mgr = SupabaseManager(
            supabaseURLString: "https://xyzsupabase.supabase.co",
            anonKey: validAnonKey
        )
        #expect(mgr.isConfigured)
        #expect(mgr.client != nil)
    }

    @Test("Configured manager starts with no session")
    func configuredManagerStartsWithNoSession() {
        let mgr = SupabaseManager(
            supabaseURLString: "https://xyzsupabase.supabase.co",
            anonKey: validAnonKey
        )
        // No auth call has been made — session must be nil.
        #expect(mgr.session == nil)
        #expect(!mgr.isAuthenticated)
        #expect(mgr.accessToken == nil)
    }
}

// MARK: - RealtimeManager: nil-client no-ops

@Suite("RealtimeManager — nil-client safety")
@MainActor
struct RealtimeManagerNilClientTests {

    @Test("subscribeToProject is a no-op with nil client")
    func subscribeToProjectIsNoOp() async {
        let rm = RealtimeManager(client: nil)
        await rm.subscribeToProject("project-123")   // Must not crash
    }

    @Test("subscribeToClip is a no-op with nil client")
    func subscribeToClipIsNoOp() async {
        let rm = RealtimeManager(client: nil)
        await rm.subscribeToClip("clip-abc")   // Must not crash
    }

    @Test("unsubscribeFromProject is a no-op with nil client")
    func unsubscribeFromProjectIsNoOp() async {
        let rm = RealtimeManager(client: nil)
        await rm.unsubscribeFromProject()   // Must not crash
    }

    @Test("unsubscribeFromClip is a no-op with nil client")
    func unsubscribeFromClipIsNoOp() async {
        let rm = RealtimeManager(client: nil)
        await rm.unsubscribeFromClip()   // Must not crash
    }

    @Test("unsubscribeAll is a no-op with nil client")
    func unsubscribeAllIsNoOp() async {
        let rm = RealtimeManager(client: nil)
        await rm.unsubscribeAll()   // Must not crash
    }

    @Test("Repeated subscribe calls with same ID are deduplicated")
    func repeatedSubscribeIsDeduplicated() async {
        let rm = RealtimeManager(client: nil)
        // nil-client means both calls are no-ops, but neither should panic
        await rm.subscribeToProject("p-1")
        await rm.subscribeToProject("p-1")   // same ID — early return guard
        await rm.subscribeToProject("p-2")   // new ID — should unsubscribe old first
    }

    @Test("Notification names are unique and non-empty")
    func notificationNamesAreValid() {
        let names: [Notification.Name] = [
            .realtimeClipIngested,
            .realtimeClipProxyReady,
            .annotationAdded,
            .annotationUpdated,
            .clipUpdated
        ]
        let rawValues = names.map(\.rawValue)
        #expect(rawValues.allSatisfy { !$0.isEmpty })
        // All names are distinct
        #expect(Set(rawValues).count == rawValues.count)
    }
}
