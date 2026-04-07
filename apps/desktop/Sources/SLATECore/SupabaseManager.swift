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
import os.log

@MainActor
public final class SupabaseManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.mountaintop.slate", category: "SupabaseManager")

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

        Self.logger.info("Initializing SupabaseManager")
        
        if urlStr.isEmpty {
            Self.logger.warning("SLATE_SUPABASE_URL environment variable not set")
        }
        if key.isEmpty {
            Self.logger.warning("SLATE_SUPABASE_ANON_KEY environment variable not set")
        }

        if let url = Self.validSupabaseURL(from: urlStr), Self.isLikelyJWT(key) {
            let c = SupabaseClient(supabaseURL: url, supabaseKey: key)
            self.client       = c
            self.isConfigured = true
            self.realtime     = RealtimeManager(client: c)
            Self.logger.info("Supabase client configured successfully")
        } else {
            self.client       = nil
            self.isConfigured = false
            self.realtime     = RealtimeManager(client: nil)
            if !urlStr.isEmpty || !key.isEmpty {
                Self.logger.error("Supabase configuration invalid - check URL and API key format")
            }
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
        guard !urlString.isEmpty else {
            logger.debug("URL string is empty")
            return nil
        }
        
        guard let url = URL(string: urlString) else {
            logger.error("Invalid URL format: \(urlString)")
            return nil
        }
        
        guard url.scheme != nil else {
            logger.error("URL missing scheme: \(urlString)")
            return nil
        }
        
        guard url.host != nil else {
            logger.error("URL missing host: \(urlString)")
            return nil
        }
        
        // Validate it's a Supabase URL
        if url.host?.contains("supabase.co") != true {
            logger.warning("URL does not appear to be a Supabase URL: \(urlString)")
            // Still allow it for development/testing
        }
        
        return url
    }

    private static func isLikelyJWT(_ value: String) -> Bool {
        guard !value.isEmpty else {
            logger.debug("JWT value is empty")
            return false
        }

        let segments = value.split(separator: ".")
        guard segments.count == 3 else {
            logger.error("JWT does not have 3 segments (found \(segments.count))")
            return false
        }

        guard let payloadData = segments[1].base64URLDecodedData else {
            logger.error("JWT payload segment is not valid base64url")
            return false
        }
        
        // Optional: Validate basic JWT structure, but don't require valid JSON
        // Some JWT-like tokens may have non-JSON payloads (e.g., encrypted tokens)
        if String(data: payloadData, encoding: .utf8) != nil {
            logger.debug("JWT payload appears to be valid UTF-8 text")
            // Try to parse as JSON for additional validation, but don't fail if it's not JSON
            do {
                _ = try JSONSerialization.jsonObject(with: payloadData)
                logger.debug("JWT payload is valid JSON")
            } catch {
                logger.debug("JWT payload is not JSON but appears valid (may be encrypted or custom format)")
            }
            return true
        } else {
            logger.debug("JWT payload is binary data (may be encrypted)")
            return true
        }
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
