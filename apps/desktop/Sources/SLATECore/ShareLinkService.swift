// SLATE — ShareLinkService
// Owned by: Claude Code
//
// C3/C4: HTTP wrapper around the Supabase edge functions defined in contracts/web-api.json.
// Provides share-link generation and proxy URL signing using real Supabase JWTs from
// `SupabaseManager.session` (see `generateShareLink(..., jwt:)` and `signProxyURL`).
//
// Configuration: set environment variables before launching:
//   SLATE_SUPABASE_URL      https://{project}.supabase.co
//   SLATE_SUPABASE_ANON_KEY  (anon/public key, not service role)

import Foundation

// MARK: - Domain models

/// Scope of a share link — mirrors contracts/web-api.json generateShareLink.body.scope.
public enum ShareLinkScope: String, CaseIterable, Codable, Sendable {
    case project
    case scene
    case subject
    case assembly

    public var displayName: String {
        switch self {
        case .project:  return "Entire Project"
        case .scene:    return "Scene"
        case .subject:  return "Subject"
        case .assembly: return "Assembly"
        }
    }
}

/// Reviewer permission flags — mirrors contracts/web-api.json generateShareLink.body.permissions.
public struct ShareLinkPermissions: Codable, Sendable {
    public var canComment: Bool
    public var canFlag: Bool
    public var canRequestAlternate: Bool

    public init(canComment: Bool, canFlag: Bool, canRequestAlternate: Bool) {
        self.canComment = canComment
        self.canFlag = canFlag
        self.canRequestAlternate = canRequestAlternate
    }

    public static let reviewOnly = ShareLinkPermissions(
        canComment: false, canFlag: false, canRequestAlternate: false
    )
    public static let fullAccess = ShareLinkPermissions(
        canComment: true, canFlag: true, canRequestAlternate: true
    )
}

/// Successful result from generate-share-link.
public struct ShareLinkResult: Sendable {
    public let token: String
    public let url: String
    public let expiresAt: String

    public init(token: String, url: String, expiresAt: String) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

/// Successful result from sign-proxy-url.
public struct SignedProxyResult: Sendable {
    public let signedUrl: String
    public let thumbnailUrl: String
    public let expiresAt: String

    public init(signedUrl: String, thumbnailUrl: String, expiresAt: String) {
        self.signedUrl = signedUrl
        self.thumbnailUrl = thumbnailUrl
        self.expiresAt = expiresAt
    }
}

/// Authentication credential passed when calling edge functions.
public enum ProxyAuth: Sendable {
    /// Full internal user — uses Supabase JWT in the Authorization header.
    case jwt(String)
    /// External reviewer — uses share token in the X-Share-Token header.
    case shareToken(String)
}

// MARK: - Errors

public enum ShareLinkError: LocalizedError, Sendable {
    case notConfigured
    case httpError(statusCode: Int, body: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Set SLATE_SUPABASE_URL and SLATE_SUPABASE_ANON_KEY."
        case .httpError(let code, let body):
            return "Server error HTTP \(code): \(body)"
        case .invalidResponse:
            return "Unexpected response format from edge function."
        }
    }
}

// MARK: - Service

/// Thread-safe HTTP wrapper for SLATE Supabase edge functions.
/// Use `ShareLinkService.shared` for the singleton; inject custom instances in tests.
public final class ShareLinkService: Sendable {
    public static let shared = ShareLinkService()

    private let supabaseURL: String
    private let supabaseAnonKey: String
    private let session: URLSession

    public init(
        supabaseURL: String? = nil,
        supabaseAnonKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.supabaseURL = supabaseURL
            ?? ProcessInfo.processInfo.environment["SLATE_SUPABASE_URL"]
            ?? ""
        self.supabaseAnonKey = supabaseAnonKey
            ?? ProcessInfo.processInfo.environment["SLATE_SUPABASE_ANON_KEY"]
            ?? ""
        self.session = session
    }

    // MARK: generate-share-link

    /// Calls the `generate-share-link` edge function.
    ///
    /// - Parameters:
    ///   - projectId: UUID of the project to share.
    ///   - scope: Granularity of the shared view (project, scene, subject, assembly).
    ///   - scopeId: Optional ID when scope is scene/subject/assembly.
    ///   - expiryHours: Hours until expiry (default 168 = 7 days).
    ///   - password: Optional access password; nil means no password.
    ///   - permissions: Reviewer interaction flags.
    ///   - jwt: Supabase JWT for the authenticated desktop user.
    public func generateShareLink(
        projectId: String,
        scope: ShareLinkScope,
        scopeId: String? = nil,
        expiryHours: Int = 168,
        password: String? = nil,
        permissions: ShareLinkPermissions = .fullAccess,
        jwt: String
    ) async throws -> ShareLinkResult {
        let url = try endpoint("generate-share-link")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyCommonHeaders(to: &request)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        struct Body: Encodable {
            let projectId: String
            let scope: String
            let scopeId: String?
            let expiryHours: Int
            let password: String?
            let permissions: ShareLinkPermissions
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(Body(
            projectId: projectId,
            scope: scope.rawValue,
            scopeId: scopeId,
            expiryHours: expiryHours,
            password: password,
            permissions: permissions
        ))

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)

        struct Response: Decodable {
            let token: String
            let url: String
            let expiresAt: String
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Response.self, from: data)
        return ShareLinkResult(token: decoded.token, url: decoded.url, expiresAt: decoded.expiresAt)
    }

    // MARK: sign-proxy-url

    /// Calls the `sign-proxy-url` edge function to obtain a presigned Cloudflare R2 URL.
    ///
    /// - Parameters:
    ///   - clipId: UUID of the clip whose proxy should be streamed.
    ///   - auth: JWT for internal users; share token for external reviewers.
    public func signProxyURL(clipId: String, auth: ProxyAuth) async throws -> SignedProxyResult {
        let url = try endpoint("sign-proxy-url")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyCommonHeaders(to: &request)
        switch auth {
        case .jwt(let token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .shareToken(let token):
            request.setValue(token, forHTTPHeaderField: "X-Share-Token")
        }

        struct Body: Encodable {
            let clipId: String
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(Body(clipId: clipId))

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, data: data)

        struct Response: Decodable {
            let signedUrl: String
            let thumbnailUrl: String
            let expiresAt: String
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Response.self, from: data)
        return SignedProxyResult(
            signedUrl: decoded.signedUrl,
            thumbnailUrl: decoded.thumbnailUrl,
            expiresAt: decoded.expiresAt
        )
    }

    // MARK: - Private helpers

    private func endpoint(_ name: String) throws -> URL {
        guard !supabaseURL.isEmpty,
              !supabaseAnonKey.isEmpty,
              let url = URL(string: "\(supabaseURL)/functions/v1/\(name)") else {
            throw ShareLinkError.notConfigured
        }
        return url
    }

    private func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("slate-desktop", forHTTPHeaderField: "X-Client-Info")
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw ShareLinkError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}
