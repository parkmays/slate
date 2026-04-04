// SLATE — SupabaseManager
// Owned by: Claude Code
//
// C4: Auth session lifecycle manager built on top of the Supabase Swift SDK v2.
//
// Configuration (set before launching):
//   SLATE_SUPABASE_URL       https://{project}.supabase.co
//   SLATE_SUPABASE_ANON_KEY  (anon/public key — not the service role key)
//
// When neither variable is set the app operates in offline mode:
//   isConfigured = false, isAuthenticated = false, client = nil.
// All callers must guard on isConfigured / isAuthenticated before using the
// Supabase client; offline-first flows must work without a session.
//
// RealtimeManager is co-owned here so both managers share one SupabaseClient.

import Foundation
import Supabase

@MainActor
public final class SupabaseManager: ObservableObject {

    // MARK: - Published state

    /// The active Supabase session, nil when signed out or not configured.
    @Published public private(set) var session: Session?
    /// True when a valid session exists.
    @Published public private(set) var isAuthenticated = false
    /// True when SLATE_SUPABASE_URL + SLATE_SUPABASE_ANON_KEY are set.
    @Published public private(set) var isConfigured: Bool
    /// True while a sign-in or sign-out network request is in flight.
    @Published public private(set) var isLoading = false
    /// Human-readable error from the most recent failed auth operation.
    @Published public var authError: String?

    // MARK: - Public read-only

    /// The underlying SupabaseClient. Nil when Supabase is not configured.
    public let client: SupabaseClient?

    /// The co-owned realtime subscription manager.
    public let realtime: RealtimeManager

    /// Current session access token, or nil when signed out.
    public var accessToken: String? { session?.accessToken }

    // MARK: - Init

    public init() {
        let urlStr = ProcessInfo.processInfo.environment["SLATE_SUPABASE_URL"] ?? ""
        let key    = ProcessInfo.processInfo.environment["SLATE_SUPABASE_ANON_KEY"] ?? ""

        if let url = Self.validSupabaseURL(from: urlStr), Self.isLikelyJWT(key) {
            let c = SupabaseClient(supabaseURL: url, supabaseKey: key)
            self.client       = c
            self.isConfigured = true
            self.realtime     = RealtimeManager(client: c)
        } else {
            self.client       = nil
            self.isConfigured = false
            self.realtime     = RealtimeManager(client: nil)
        }
    }

    // MARK: - Init (test seam)

    /// Package-internal initializer for unit tests.
    /// Bypasses env-var lookup so tests can supply exact values without
    /// mutating ProcessInfo.
    init(supabaseURLString: String, anonKey: String) {
        if let url = Self.validSupabaseURL(from: supabaseURLString), Self.isLikelyJWT(anonKey) {
            let c = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
            self.client       = c
            self.isConfigured = true
            self.realtime     = RealtimeManager(client: c)
        } else {
            self.client       = nil
            self.isConfigured = false
            self.realtime     = RealtimeManager(client: nil)
        }
    }

    // MARK: - Auth state listener

    /// Starts the auth event loop. Call once from SLATEApp.setupApp().
    /// Suspends until the app exits — run in a detached Task if needed.
    public func startListeningToAuthState() async {
        guard let client else { return }
        for await (event, session) in client.auth.authStateChanges {
            handle(event: event, session: session)
        }
    }

    // MARK: - Sign in

    /// Signs in with email + password. Sets authError on failure.
    public func signIn(email: String, password: String) async {
        guard let client else {
            authError = "Supabase is not configured."
            return
        }
        isLoading = true
        authError = nil
        do {
            try await client.auth.signIn(email: email, password: password)
            // session / isAuthenticated are updated by the authStateChanges listener.
        } catch {
            authError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Sign out

    /// Signs out and tears down all realtime subscriptions.
    public func signOut() async {
        guard let client else { return }
        isLoading = true
        do {
            try await client.auth.signOut()
        } catch {
            // Network errors during sign-out are non-fatal.
            // Local state is cleared regardless.
        }
        session         = nil
        isAuthenticated = false
        isLoading       = false
        await realtime.unsubscribeAll()
    }

    // MARK: - Private

    private func handle(event: AuthChangeEvent, session: Session?) {
        switch event {
        case .initialSession:
            self.session         = session
            self.isAuthenticated = session != nil
        case .signedIn, .tokenRefreshed:
            self.session         = session
            self.isAuthenticated = true
            authError            = nil
        case .signedOut, .userDeleted:
            self.session         = nil
            self.isAuthenticated = false
        default:
            break
        }
    }

    private static func validSupabaseURL(from urlString: String) -> URL? {
        guard !urlString.isEmpty, let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    private static func isLikelyJWT(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }

        let segments = value.split(separator: ".")
        guard segments.count == 3 else {
            return false
        }

        return segments[1].base64URLDecodedData != nil
    }
}

private extension Substring {
    var base64URLDecodedData: Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = base64.count % 4
        if padding != 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }

        return Data(base64Encoded: base64)
    }
}
