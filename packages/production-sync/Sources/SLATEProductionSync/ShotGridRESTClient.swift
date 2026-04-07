import Foundation

public enum ShotGridRESTError: Error, Sendable {
    case invalidURL
    case http(Int, String?)
    case tokenPayload
}

/// Script / application credentials (client_credentials) against `https://{site}.shotgunstudio.com/api/v1/auth/access_token`.
public final class ShotGridRESTClient: Sendable {
    private let siteSubdomain: String
    private let scriptName: String
    private let applicationKey: String
    private let session: URLSession

    public init(siteSubdomain: String, scriptName: String, applicationKey: String, session: URLSession = .shared) {
        self.siteSubdomain = siteSubdomain
        self.scriptName = scriptName
        self.applicationKey = applicationKey
        self.session = session
    }

    private var tokenURL: URL? {
        if siteSubdomain.contains(".") {
            let base = siteSubdomain.hasPrefix("http") ? siteSubdomain : "https://\(siteSubdomain)"
            return URL(string: "\(base)/api/v1/auth/access_token")
        }
        return URL(string: "https://\(siteSubdomain).shotgunstudio.com/api/v1/auth/access_token")
    }

    /// Obtains a bearer token for subsequent REST calls (cache and refresh in the orchestrator).
    public func fetchAccessToken() async throws -> String {
        guard let url = tokenURL else {
            throw ShotGridRESTError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body =
            "grant_type=client_credentials&client_id=\(scriptName.urlFormEncoded)&client_secret=\(applicationKey.urlFormEncoded)"
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShotGridRESTError.http(-1, nil)
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw ShotGridRESTError.http(http.statusCode, String(data: data, encoding: .utf8))
        }
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = obj["access_token"] as? String
        else {
            throw ShotGridRESTError.tokenPayload
        }
        return token
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
