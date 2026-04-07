import Foundation

struct BridgeClip: Decodable {
    let id: String
    let projectId: String
    let sourcePath: String
    let reviewStatus: String
    let proxyPath: String?
}

enum BridgeClient {
    private static let baseURL = URL(string: "http://127.0.0.1:8544")!

    static func listClips(projectId: String?) async throws -> [BridgeClip] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/nle/clips"), resolvingAgainstBaseURL: false)!
        if let projectId {
            components.queryItems = [URLQueryItem(name: "projectId", value: projectId)]
        }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode([BridgeClip].self, from: data)
    }
}
