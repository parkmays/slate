import Foundation
import Network

public struct NLEBridgePluginDescriptor: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let protocolVersion: String
}

public struct NLEBridgeProject: Codable, Sendable {
    public let id: String
    public let name: String
}

public struct NLEBridgeClip: Codable, Sendable {
    public let id: String
    public let projectId: String
    public let sourcePath: String
    public let reviewStatus: String
    public let proxyPath: String?
}

private struct NLEBridgeHealth: Codable {
    let service: String
    let status: String
    let port: Int
}

public actor NLEPluginBridgeService {
    private let listener: NWListener
    private let port: UInt16
    private let projectProvider: @Sendable () async -> [NLEBridgeProject]
    private let clipProvider: @Sendable (_ projectId: String?) async -> [NLEBridgeClip]

    public init(
        port: UInt16 = 8544,
        projectProvider: @escaping @Sendable () async -> [NLEBridgeProject] = { [] },
        clipProvider: @escaping @Sendable (_ projectId: String?) async -> [NLEBridgeClip] = { _ in [] }
    ) throws {
        self.port = port
        self.projectProvider = projectProvider
        self.clipProvider = clipProvider
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection) }
        }
        listener.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    public func stop() {
        listener.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, _, _ in
            guard let self, let data, let raw = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            Task {
                let response = await self.route(rawRequest: raw)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func route(rawRequest: String) async -> Data {
        let line = rawRequest.components(separatedBy: "\r\n").first ?? ""
        let pieces = line.split(separator: " ")
        guard pieces.count >= 2 else {
            return http(status: "400 Bad Request", body: "Bad request")
        }
        let method = String(pieces[0])
        let path = String(pieces[1])

        if method == "GET", path.hasPrefix("/api/nle/health") {
            return json(status: "200 OK", payload: NLEBridgeHealth(service: "slate-nle-bridge", status: "ok", port: Int(port)))
        }
        if method == "GET", path.hasPrefix("/api/nle/plugins") {
            let plugins: [NLEBridgePluginDescriptor] = [
                .init(id: "adobe-uxp", displayName: "Adobe Premiere / After Effects (UXP)", protocolVersion: "1.0"),
                .init(id: "resolve-workflow", displayName: "DaVinci Resolve Workflow", protocolVersion: "1.0"),
                .init(id: "fcp-extension", displayName: "Final Cut Pro Workflow Extension", protocolVersion: "1.0"),
                .init(id: "avid-panel", displayName: "Avid MediaCentral Panel", protocolVersion: "1.0"),
            ]
            return json(status: "200 OK", payload: plugins)
        }
        if method == "GET", path.hasPrefix("/api/nle/projects") {
            let projects = await projectProvider()
            return json(status: "200 OK", payload: projects)
        }
        if method == "GET", path.hasPrefix("/api/nle/clips") {
            let queryProjectId = URLComponents(string: "http://localhost\(path)")?
                .queryItems?
                .first(where: { $0.name == "projectId" })?
                .value
            let clips = await clipProvider(queryProjectId)
            return json(status: "200 OK", payload: clips)
        }

        return http(status: "404 Not Found", body: "Unknown route")
    }

    private func json<T: Encodable>(status: String, payload: T) -> Data {
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return response(status: status, contentType: "application/json", body: data)
    }

    private func http(status: String, body: String) -> Data {
        response(status: status, contentType: "text/plain", body: Data(body.utf8))
    }

    private func response(status: String, contentType: String, body: Data) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
        head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
