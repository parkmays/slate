import AppKit
import CryptoKit
import Foundation
import Network
import Security
import SwiftUI

public struct CloudOAuthClientConfiguration: Codable, Sendable, Equatable {
    public var clientId: String
    public var clientSecret: String?

    public init(clientId: String = "", clientSecret: String? = nil) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

public struct CloudProviderAccount: Codable, Identifiable, Sendable, Equatable {
    public var provider: CloudSyncProvider
    public var displayName: String
    public var email: String?
    public var accountId: String?
    public var connectedAt: String
    public var expiresAt: String?

    public var id: String { provider.rawValue }

    public init(
        provider: CloudSyncProvider,
        displayName: String,
        email: String? = nil,
        accountId: String? = nil,
        connectedAt: String = ISO8601DateFormatter().string(from: Date()),
        expiresAt: String? = nil
    ) {
        self.provider = provider
        self.displayName = displayName
        self.email = email
        self.accountId = accountId
        self.connectedAt = connectedAt
        self.expiresAt = expiresAt
    }
}

public enum CloudAuthError: LocalizedError {
    case missingClientConfiguration(CloudSyncProvider)
    case missingCredentials(CloudSyncProvider)
    case invalidRedirectResponse
    case invalidRedirectState
    case authorizationDenied(String)
    case tokenExchangeFailed(String)
    case keychainFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientConfiguration(let provider):
            return "Add an OAuth client ID for \(provider.displayName) before connecting."
        case .missingCredentials(let provider):
            return "No stored credentials were found for \(provider.displayName)."
        case .invalidRedirectResponse:
            return "The provider returned an invalid browser redirect."
        case .invalidRedirectState:
            return "The browser redirect did not match the original authorization request."
        case .authorizationDenied(let message):
            return message
        case .tokenExchangeFailed(let message):
            return message
        case .keychainFailure(let message):
            return message
        }
    }
}

@MainActor
public final class CloudAuthManager: ObservableObject {
    @Published public private(set) var accounts: [CloudProviderAccount] = []
    @Published public private(set) var configurations: [CloudSyncProvider: CloudOAuthClientConfiguration] = [:]
    @Published public private(set) var connectingProvider: CloudSyncProvider?
    @Published public var errorMessage: String?

    private let userDefaults: UserDefaults
    private let keychain: KeychainStore
    private var credentialsByProvider: [CloudSyncProvider: CloudOAuthCredential] = [:]

    private static let configurationDefaultsKey = "com.mountaintop.slate.cloud-auth.configurations"

    public init(
        userDefaults: UserDefaults = .standard,
        keychainServiceName: String = "com.mountaintop.slate.cloud-auth"
    ) {
        self.userDefaults = userDefaults
        self.keychain = KeychainStore(service: keychainServiceName)
        loadPersistedState()
    }

    public func configuration(for provider: CloudSyncProvider) -> CloudOAuthClientConfiguration {
        effectiveConfiguration(for: provider)
    }

    public func account(for provider: CloudSyncProvider) -> CloudProviderAccount? {
        credentialsByProvider[provider]?.account
    }

    public func hasConnectedAccount(for provider: CloudSyncProvider) -> Bool {
        account(for: provider) != nil || hasEnvironmentToken(for: provider)
    }

    public func hasEnvironmentToken(for provider: CloudSyncProvider) -> Bool {
        guard let token = ProcessInfo.processInfo.environment[provider.tokenEnvironmentVariable] else {
            return false
        }

        return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func saveConfiguration(
        for provider: CloudSyncProvider,
        clientId: String,
        clientSecret: String?
    ) {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientSecret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        configurations[provider] = CloudOAuthClientConfiguration(
            clientId: trimmedClientId,
            clientSecret: trimmedClientSecret?.isEmpty == false ? trimmedClientSecret : nil
        )
        persistConfigurations()
    }

    public func disconnect(provider: CloudSyncProvider) throws {
        try keychain.remove(account: provider.rawValue)
        credentialsByProvider.removeValue(forKey: provider)
        refreshAccounts()
    }

    public func connect(provider: CloudSyncProvider) async throws {
        if provider == .amazonS3 {
            throw CloudAuthError.tokenExchangeFailed("Amazon S3 uses access-key credentials (SLATE_S3_* env vars) and does not require OAuth connect.")
        }
        let descriptor = OAuthProviderDescriptor.make(for: provider)
        let configuration = effectiveConfiguration(for: provider)
        guard !configuration.clientId.isEmpty else {
            throw CloudAuthError.missingClientConfiguration(provider)
        }

        connectingProvider = provider
        errorMessage = nil
        defer { connectingProvider = nil }

        let pkce = PKCEChallenge.generate()
        let state = randomOAuthToken(byteCount: 24)
        let loopbackServer = OAuthLoopbackServer()
        let redirectURI = try await loopbackServer.start()
        let authorizationURL = try descriptor.authorizationURL(
            configuration: configuration,
            redirectURI: redirectURI,
            state: state,
            codeChallenge: pkce.challenge
        )

        NSWorkspace.shared.open(authorizationURL)

        let callback = try await loopbackServer.waitForCallback()
        if let error = callback.error {
            throw CloudAuthError.authorizationDenied(error)
        }

        guard callback.state == state else {
            throw CloudAuthError.invalidRedirectState
        }

        guard let code = callback.code, !code.isEmpty else {
            throw CloudAuthError.invalidRedirectResponse
        }

        let tokenResponse = try await exchangeCode(
            provider: provider,
            configuration: configuration,
            redirectURI: redirectURI,
            authorizationCode: code,
            codeVerifier: pkce.verifier
        )

        let account = await fetchAccount(
            provider: provider,
            accessToken: tokenResponse.accessToken,
            expiresAt: tokenResponse.expiresAt
        )

        let credential = CloudOAuthCredential(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: tokenResponse.tokenType,
            scope: tokenResponse.scope,
            expiresAt: tokenResponse.expiresAt,
            account: account
        )

        try saveCredential(credential, for: provider)
        errorMessage = nil
    }

    public func validAccessToken(for provider: CloudSyncProvider) async throws -> String {
        if let envToken = ProcessInfo.processInfo.environment[provider.tokenEnvironmentVariable],
           !envToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envToken
        }

        guard var credential = credentialsByProvider[provider] else {
            throw CloudAuthError.missingCredentials(provider)
        }

        if credential.isExpiringSoon {
            credential = try await refreshCredential(for: provider, credential: credential)
            try saveCredential(credential, for: provider)
        }

        return credential.accessToken
    }

    private func loadPersistedState() {
        if let data = userDefaults.data(forKey: Self.configurationDefaultsKey),
           let persisted = try? JSONDecoder().decode([String: CloudOAuthClientConfiguration].self, from: data) {
            configurations = Dictionary(
                uniqueKeysWithValues: persisted.compactMap { key, value in
                    guard let provider = CloudSyncProvider(rawValue: key) else {
                        return nil
                    }
                    return (provider, value)
                }
            )
        }

        for provider in CloudSyncProvider.allCases {
            guard let data = try? keychain.read(account: provider.rawValue),
                  let credential = try? JSONDecoder.cloudAuthOAuth.decode(CloudOAuthCredential.self, from: data)
            else {
                continue
            }

            credentialsByProvider[provider] = credential
        }

        refreshAccounts()
    }

    private func persistConfigurations() {
        let payload = Dictionary(
            uniqueKeysWithValues: configurations.map { ($0.key.rawValue, $0.value) }
        )

        if let data = try? JSONEncoder().encode(payload) {
            userDefaults.set(data, forKey: Self.configurationDefaultsKey)
        }
    }

    private func refreshAccounts() {
        accounts = credentialsByProvider
            .values
            .map(\.account)
            .sorted { $0.provider.displayName < $1.provider.displayName }
    }

    private func effectiveConfiguration(for provider: CloudSyncProvider) -> CloudOAuthClientConfiguration {
        let persisted = configurations[provider] ?? .init()
        let envClientId = ProcessInfo.processInfo.environment[provider.oauthClientIdEnvironmentVariable] ?? ""
        let envClientSecret = provider.oauthClientSecretEnvironmentVariable.flatMap {
            ProcessInfo.processInfo.environment[$0]
        }

        return CloudOAuthClientConfiguration(
            clientId: persisted.clientId.isEmpty ? envClientId : persisted.clientId,
            clientSecret: persisted.clientSecret ?? envClientSecret
        )
    }

    private func saveCredential(_ credential: CloudOAuthCredential, for provider: CloudSyncProvider) throws {
        let data = try JSONEncoder().encode(credential)
        try keychain.write(data, account: provider.rawValue)
        credentialsByProvider[provider] = credential
        refreshAccounts()
    }

    private func exchangeCode(
        provider: CloudSyncProvider,
        configuration: CloudOAuthClientConfiguration,
        redirectURI: String,
        authorizationCode: String,
        codeVerifier: String
    ) async throws -> OAuthTokenResponse {
        let descriptor = OAuthProviderDescriptor.make(for: provider)
        var request = URLRequest(url: descriptor.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "grant_type": "authorization_code",
            "client_id": configuration.clientId,
            "client_secret": configuration.clientSecret,
            "code": authorizationCode,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateTokenResponse(response: response, data: data, provider: provider)
        return try JSONDecoder.cloudAuthOAuth.decode(OAuthTokenResponse.self, from: data)
    }

    private func refreshCredential(
        for provider: CloudSyncProvider,
        credential: CloudOAuthCredential
    ) async throws -> CloudOAuthCredential {
        let configuration = effectiveConfiguration(for: provider)
        guard !configuration.clientId.isEmpty else {
            throw CloudAuthError.missingClientConfiguration(provider)
        }
        guard let refreshToken = credential.refreshToken, !refreshToken.isEmpty else {
            throw CloudAuthError.missingCredentials(provider)
        }

        let descriptor = OAuthProviderDescriptor.make(for: provider)
        var request = URLRequest(url: descriptor.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "grant_type": "refresh_token",
            "client_id": configuration.clientId,
            "client_secret": configuration.clientSecret,
            "refresh_token": refreshToken
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateTokenResponse(response: response, data: data, provider: provider)
        let refreshed = try JSONDecoder.cloudAuthOAuth.decode(OAuthTokenResponse.self, from: data)

        return CloudOAuthCredential(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? credential.refreshToken,
            tokenType: refreshed.tokenType ?? credential.tokenType,
            scope: refreshed.scope ?? credential.scope,
            expiresAt: refreshed.expiresAt,
            account: credential.account.updated(expiresAt: refreshed.expiresAt)
        )
    }

    private func validateTokenResponse(
        response: URLResponse,
        data: Data,
        provider: CloudSyncProvider
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAuthError.tokenExchangeFailed("No HTTP response returned by \(provider.displayName).")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw CloudAuthError.tokenExchangeFailed(
                "\(provider.displayName) rejected the token exchange: \(message)"
            )
        }
    }

    private func fetchAccount(
        provider: CloudSyncProvider,
        accessToken: String,
        expiresAt: String?
    ) async -> CloudProviderAccount {
        do {
            switch provider {
            case .googleDrive:
                return try await fetchGoogleAccount(accessToken: accessToken, expiresAt: expiresAt)
            case .dropbox:
                return try await fetchDropboxAccount(accessToken: accessToken, expiresAt: expiresAt)
            case .amazonS3:
                return CloudProviderAccount(
                    provider: .amazonS3,
                    displayName: "Amazon S3",
                    email: nil,
                    accountId: ProcessInfo.processInfo.environment["SLATE_S3_BUCKET"],
                    expiresAt: nil
                )
            case .frameIO:
                return try await fetchFrameIOAccount(accessToken: accessToken, expiresAt: expiresAt)
            }
        } catch {
            return CloudProviderAccount(
                provider: provider,
                displayName: "\(provider.displayName) Account",
                expiresAt: expiresAt
            )
        }
    }

    private func fetchGoogleAccount(accessToken: String, expiresAt: String?) async throws -> CloudProviderAccount {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder().decode(GoogleAccountPayload.self, from: data)
        return CloudProviderAccount(
            provider: .googleDrive,
            displayName: payload.name ?? payload.email ?? "Google Drive",
            email: payload.email,
            accountId: payload.id,
            expiresAt: expiresAt
        )
    }

    private func fetchDropboxAccount(accessToken: String, expiresAt: String?) async throws -> CloudProviderAccount {
        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/users/get_current_account")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder.cloudAuthDropbox.decode(DropboxAccountPayload.self, from: data)
        return CloudProviderAccount(
            provider: .dropbox,
            displayName: payload.name.displayName,
            email: payload.email,
            accountId: payload.accountId,
            expiresAt: expiresAt
        )
    }

    private func fetchFrameIOAccount(accessToken: String, expiresAt: String?) async throws -> CloudProviderAccount {
        var request = URLRequest(url: URL(string: "https://api.frame.io/v4/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let payload = try JSONDecoder.cloudAuthFrameIO.decode(FrameIOAccountPayload.self, from: data)
        return CloudProviderAccount(
            provider: .frameIO,
            displayName: payload.name ?? payload.email ?? "Frame.io",
            email: payload.email,
            accountId: payload.accountId ?? payload.id,
            expiresAt: expiresAt
        )
    }

    private func formEncodedBody(_ values: [String: String?]) -> Data? {
        let encodedPairs = values.compactMap { key, value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }

            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }

        return Data(encodedPairs.joined(separator: "&").utf8)
    }

}

private struct CloudOAuthCredential: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let scope: String?
    let expiresAt: String?
    let account: CloudProviderAccount

    var isExpiringSoon: Bool {
        guard let expiresAt,
              let expiryDate = ISO8601DateFormatter().date(from: expiresAt)
        else {
            return false
        }

        return expiryDate.timeIntervalSinceNow < 90
    }
}

private struct OAuthProviderDescriptor: Sendable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let scopes: [String]
    let additionalAuthorizationItems: [URLQueryItem]

    static func make(for provider: CloudSyncProvider) -> OAuthProviderDescriptor {
        switch provider {
        case .googleDrive:
            return OAuthProviderDescriptor(
                authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: [
                    "openid",
                    "email",
                    "profile",
                    "https://www.googleapis.com/auth/drive.file"
                ],
                additionalAuthorizationItems: [
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent")
                ]
            )
        case .dropbox:
            return OAuthProviderDescriptor(
                authorizationEndpoint: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
                tokenEndpoint: URL(string: "https://api.dropboxapi.com/oauth2/token")!,
                scopes: [
                    "account_info.read",
                    "files.metadata.read",
                    "files.content.read",
                    "files.content.write",
                    "sharing.read",
                    "sharing.write"
                ],
                additionalAuthorizationItems: [
                    URLQueryItem(name: "token_access_type", value: "offline")
                ]
            )
        case .amazonS3:
            return OAuthProviderDescriptor(
                authorizationEndpoint: URL(string: "https://example.invalid/s3/no-oauth")!,
                tokenEndpoint: URL(string: "https://example.invalid/s3/no-oauth")!,
                scopes: [],
                additionalAuthorizationItems: []
            )
        case .frameIO:
            return OAuthProviderDescriptor(
                authorizationEndpoint: URL(string: "https://ims-na1.adobelogin.com/ims/authorize/v2")!,
                tokenEndpoint: URL(string: "https://ims-na1.adobelogin.com/ims/token/v3")!,
                scopes: [
                    "openid",
                    "AdobeID",
                    "offline_access",
                    "additional_info.projectedProductContext"
                ],
                additionalAuthorizationItems: []
            )
        }
    }

    func authorizationURL(
        configuration: CloudOAuthClientConfiguration,
        redirectURI: String,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        guard var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw CloudAuthError.invalidRedirectResponse
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ] + additionalAuthorizationItems

        guard let url = components.url else {
            throw CloudAuthError.invalidRedirectResponse
        }

        return url
    }
}

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String?
    let refreshToken: String?
    let scope: String?
    let expiresIn: Int?

    var expiresAt: String? {
        guard let expiresIn else {
            return nil
        }

        return ISO8601DateFormatter().string(from: Date().addingTimeInterval(TimeInterval(expiresIn)))
    }
}

private struct GoogleAccountPayload: Decodable {
    let id: String?
    let email: String?
    let name: String?
}

private struct DropboxAccountPayload: Decodable {
    struct Name: Decodable {
        let displayName: String
    }

    let accountId: String?
    let email: String?
    let name: Name
}

private struct FrameIOAccountPayload: Decodable {
    let id: String?
    let name: String?
    let email: String?
    let accountId: String?
}

private struct OAuthCallbackPayload: Sendable {
    let code: String?
    let state: String?
    let error: String?
}

private final actor OAuthLoopbackServer {
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<Int, Error>?
    private var callbackContinuation: CheckedContinuation<OAuthCallbackPayload, Error>?
    private let queue = DispatchQueue(label: "com.mountaintop.slate.oauth-loopback")

    func start() async throws -> String {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else {
                return
            }

            switch state {
            case .ready:
                if let port = listener.port?.rawValue {
                    Task {
                        await self.resumeStart(with: .success(Int(port)))
                    }
                }
            case .failed(let error):
                Task {
                    await self.resumeStart(with: .failure(error))
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                return
            }

            connection.start(queue: self.queue)
            Task {
                await self.receive(on: connection)
            }
        }

        listener.start(queue: queue)

        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            startContinuation = continuation
        }

        return "http://127.0.0.1:\(port)/oauth/callback"
    }

    func waitForCallback() async throws -> OAuthCallbackPayload {
        try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation
        }
    }

    private func resumeStart(with result: Result<Int, Error>) {
        guard let continuation = startContinuation else {
            return
        }
        startContinuation = nil
        continuation.resume(with: result)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else {
                return
            }

            Task {
                await self.handle(data: data, error: error, connection: connection)
            }
        }
    }

    private func handle(data: Data?, error: NWError?, connection: NWConnection) {
        defer {
            sendCompletionPage(on: connection)
            connection.cancel()
            listener?.cancel()
            listener = nil
        }

        if let error {
            callbackContinuation?.resume(throwing: error)
            callbackContinuation = nil
            return
        }

        guard let data,
              let request = String(data: data, encoding: .utf8),
              let requestLine = request.split(separator: "\r\n").first,
              let pathComponent = requestLine.split(separator: " ").dropFirst().first,
              let requestURL = URL(string: "http://127.0.0.1\(pathComponent)")
        else {
            callbackContinuation?.resume(throwing: CloudAuthError.invalidRedirectResponse)
            callbackContinuation = nil
            return
        }

        let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
        let errorValue = components?.queryItems?.first(where: { $0.name == "error" })?.value

        callbackContinuation?.resume(returning: OAuthCallbackPayload(code: code, state: state, error: errorValue))
        callbackContinuation = nil
    }

    private func sendCompletionPage(on connection: NWConnection) {
        let html = """
        <html>
        <head><title>SLATE Cloud Sync</title></head>
        <body style="font-family:-apple-system,system-ui,sans-serif;padding:32px;">
        <h2>SLATE is connected</h2>
        <p>You can close this browser window and return to the desktop app.</p>
        </body>
        </html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """

        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }
}

private struct PKCEChallenge {
    let verifier: String
    let challenge: String

    static func generate() -> PKCEChallenge {
        let verifier = randomOAuthToken(byteCount: 48)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCEChallenge(verifier: verifier, challenge: challenge)
    }
}

private func randomOAuthToken(byteCount: Int) -> String {
    let data = Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max) })
    return data.base64URLEncodedString()
}

private struct KeychainStore {
    let service: String

    func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw CloudAuthError.keychainFailure(status.message)
        }

        return result as? Data
    }

    func write(_ data: Data, account: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            let insertStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw CloudAuthError.keychainFailure(insertStatus.message)
            }
            return
        }

        guard status == errSecSuccess else {
            throw CloudAuthError.keychainFailure(status.message)
        }
    }

    func remove(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudAuthError.keychainFailure(status.message)
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension JSONDecoder {
    static var cloudAuthOAuth: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var cloudAuthDropbox: JSONDecoder {
        cloudAuthOAuth
    }

    static var cloudAuthFrameIO: JSONDecoder {
        cloudAuthOAuth
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return allowed
    }()
}

private extension OSStatus {
    var message: String {
        SecCopyErrorMessageString(self, nil) as String? ?? "OSStatus \(self)"
    }
}

private extension CloudProviderAccount {
    func updated(expiresAt: String?) -> CloudProviderAccount {
        CloudProviderAccount(
            provider: provider,
            displayName: displayName,
            email: email,
            accountId: accountId,
            connectedAt: connectedAt,
            expiresAt: expiresAt
        )
    }
}

private extension CloudSyncProvider {
    var oauthClientIdEnvironmentVariable: String {
        switch self {
        case .googleDrive:
            return "SLATE_GOOGLE_DRIVE_CLIENT_ID"
        case .dropbox:
            return "SLATE_DROPBOX_APP_KEY"
        case .amazonS3:
            return "SLATE_S3_ACCESS_KEY_ID"
        case .frameIO:
            return "SLATE_FRAMEIO_CLIENT_ID"
        }
    }

    var oauthClientSecretEnvironmentVariable: String? {
        switch self {
        case .googleDrive:
            return nil
        case .dropbox:
            return "SLATE_DROPBOX_APP_SECRET"
        case .amazonS3:
            return "SLATE_S3_SECRET_ACCESS_KEY"
        case .frameIO:
            return "SLATE_FRAMEIO_CLIENT_SECRET"
        }
    }
}
