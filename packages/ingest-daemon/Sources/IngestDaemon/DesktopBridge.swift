// SLATE — DesktopBridge
// Owned by: Claude Code
//
// Simple JSON socket server on localhost for SwiftUI app to observe ingest state.
// Exposes IngestProgressReport via HTTP endpoints and WebSocket for real-time updates.

import Foundation
import Network
import SLATESharedTypes

public actor DesktopBridge {
    private let listener: NWListener
    private let dbQueue: DatabaseQueue
    private var connectedClients: Set<NWConnection> = []
    private var progressReport: IngestProgressReport?
    
    public init(port: UInt16 = 8080, dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        
        // Create TCP listener
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.allowFastOpen = true
        
        self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        // Set up connection handlers
        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }
        
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Desktop bridge listening on port 8080")
            case .failed(let error):
                print("Desktop bridge failed: \(error)")
            case .cancelled:
                print("Desktop bridge cancelled")
            default:
                break
            }
        }
    }
    
    public func start() throws {
        listener.start(queue: DispatchQueue.global())
    }
    
    public func stop() {
        listener.cancel()
        for client in connectedClients {
            client.cancel()
        }
        connectedClients.removeAll()
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connectedClients.insert(connection)
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state, case .cancelled = state {
                Task {
                    await self?.connectedClients.remove(connection)
                }
            }
        }
        
        connection.start(queue: DispatchQueue.global())
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = content, !data.isEmpty {
                Task {
                    await self.handleRequest(data, connection: connection)
                }
            }
            
            if !isComplete {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    // Continue receiving
                }
            }
        }
    }
    
    private func handleRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        
        // Parse HTTP request
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        Task {
            let response = await self.routeRequest(method: method, path: path)
            connection.send(content: response, completion: .idempotent)
        }
    }
    
    private func routeRequest(method: String, path: String) async -> Data {
        switch (method, path) {
        case ("GET", "/api/progress"):
            return await getProgressResponse()
        case ("GET", "/api/clips"):
            return await getClipsResponse()
        case ("GET", "/api/projects"):
            return await getProjectsResponse()
        case ("GET", "/api/watch-folders"):
            return await getWatchFoldersResponse()
        default:
            return httpResponse(status: "404 Not Found", body: "Not Found")
        }
    }
    
    private func getProgressResponse() async -> Data {
        do {
            let report = try await getIngestProgressReport()
            let jsonData = try JSONEncoder().encode(report)
            return httpResponse(status: "200 OK", body: jsonData, contentType: "application/json")
        } catch {
            return httpResponse(status: "500 Internal Server Error", body: "Error: \(error.localizedDescription)")
        }
    }
    
    private func getClipsResponse() async -> Data {
        do {
            // Get project ID from query params (simplified)
            let clips = try await getClips(forProjectId: "default", limit: 100)
            let jsonData = try JSONEncoder().encode(clips)
            return httpResponse(status: "200 OK", body: jsonData, contentType: "application/json")
        } catch {
            return httpResponse(status: "500 Internal Server Error", body: "Error: \(error.localizedDescription)")
        }
    }
    
    private func getProjectsResponse() async -> Data {
        do {
            let projects = try await getAllProjects()
            let jsonData = try JSONEncoder().encode(projects)
            return httpResponse(status: "200 OK", body: jsonData, contentType: "application/json")
        } catch {
            return httpResponse(status: "500 Internal Server Error", body: "Error: \(error.localizedDescription)")
        }
    }
    
    private func getWatchFoldersResponse() async -> Data {
        do {
            let watchFolders = try await getWatchFolders()
            let jsonData = try JSONEncoder().encode(watchFolders)
            return httpResponse(status: "200 OK", body: jsonData, contentType: "application/json")
        } catch {
            return httpResponse(status: "500 Internal Server Error", body: "Error: \(error.localizedDescription)")
        }
    }
    
    private func httpResponse(status: String, body: Data, contentType: String = "text/plain") -> Data {
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Access-Control-Allow-Methods: GET, POST, PUT, DELETE\r\n"
        response += "Access-Control-Allow-Headers: Content-Type\r\n"
        response += "\r\n"
        
        var responseData = Data(response.utf8)
        responseData.append(body)
        return responseData
    }
    
    private func httpResponse(status: String, body: String, contentType: String = "text/plain") -> Data {
        guard let bodyData = body.data(using: .utf8) else {
            return Data()
        }
        return httpResponse(status: status, body: bodyData, contentType: contentType)
    }
    
    // MARK: - Broadcast Updates
    
    public func broadcastProgressUpdate(_ report: IngestProgressReport) {
        self.progressReport = report

        let message: [String: Any] = [
            "type": "progress_update",
            "data": report
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message) else { return }

        for client in connectedClients {
            client.send(content: jsonData, completion: .idempotent)
        }
    }

    public func broadcastClipUpdate(_ clip: Clip) {
        var clipData: [String: Any] = [
            "id": clip.id,
            "projectId": clip.projectId,
            "checksum": clip.checksum,
            "sourcePath": clip.sourcePath,
            "sourceSize": clip.sourceSize,
            "sourceFormat": clip.sourceFormat.rawValue,
            "sourceFps": clip.sourceFps,
            "sourceTimecodeStart": clip.sourceTimecodeStart,
            "duration": clip.duration,
            "proxyPath": clip.proxyPath as Any,
            "proxyStatus": clip.proxyStatus.rawValue,
            "syncResult": clip.syncResult,
            "syncedAudioPath": clip.syncedAudioPath as Any,
            "aiScores": clip.aiScores as Any,
            "transcriptId": clip.transcriptId as Any,
            "aiProcessingStatus": clip.aiProcessingStatus.rawValue,
            "reviewStatus": clip.reviewStatus.rawValue,
            "approvalStatus": clip.approvalStatus.rawValue,
            "ingestedAt": clip.ingestedAt,
            "updatedAt": clip.updatedAt,
            "projectMode": clip.projectMode.rawValue
        ]

        let message: [String: Any] = [
            "type": "clip_updated",
            "data": clipData
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: message) else { return }

        for client in connectedClients {
            client.send(content: jsonData, completion: .idempotent)
        }
    }

    // MARK: - Helper Methods (simplified implementations)
    
    private func getIngestProgressReport() async throws -> IngestProgressReport {
        // This would be implemented in GRDBStore
        return IngestProgressReport(
            activeItems: [],
            totalProcessed: 0,
            totalQueued: 0
        )
    }
    
    private func getClips(forProjectId projectId: String, limit: Int) async throws -> [Clip] {
        try await dbQueue.read { db in
            try Clip
                .filter(Column("project_id") == projectId)
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    private func getAllProjects() async throws -> [Project] {
        try await dbQueue.read { db in
            try Project.order(Column("created_at").desc).fetchAll(db)
        }
    }
    
    private func getWatchFolders() async throws -> [WatchFolderRecord] {
        try await dbQueue.read { db in
            try WatchFolderRecord.order(Column("created_at").desc).fetchAll(db)
        }
    }
}

// MARK: - WebSocket Support (Optional Enhancement)

public actor WebSocketBridge {
    private let listener: NWListener
    private var connections: Set<NWConnection> = []
    
    public init(port: UInt16 = 8081) throws {
        let parameters = NWParameters.tcp
        let websocketOptions = NWProtocolWebSocket.Options()
        websocketOptions.autoPingTimeout = 30
        websocketOptions.maxFrameSize = 1 << 20 // 1MB
        
        parameters.defaultProtocolStack.insert(.websocket(websocketOptions), at: 0)
        
        self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleWebSocketConnection(connection)
            }
        }
    }
    
    public func start() throws {
        listener.start(queue: DispatchQueue.global())
    }
    
    public func stop() {
        listener.cancel()
    }
    
    private func handleWebSocketConnection(_ connection: NWConnection) {
        connections.insert(connection)
        
        connection.start(queue: DispatchQueue.global())
        
        // Handle WebSocket messages
        connection.receiveMessage { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = content {
                Task {
                    await self.handleWebSocketMessage(data, connection: connection)
                }
            }
            
            if !isComplete {
                connection.receiveMessage { content, _, isComplete, error in
                    // Continue receiving
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ content: NWProtocolWebSocket.Message, connection: NWConnection) {
        switch content {
        case .data(let data):
            // Handle binary message
            break
        case .string(let string):
            // Handle text message
            handleWebSocketCommand(string, connection: connection)
        @unknown default:
            break
        }
    }
    
    private func handleWebSocketCommand(_ command: String, connection: NWConnection) {
        // Parse command like "subscribe:progress"
        let components = command.components(separatedBy: ":")
        guard components.count >= 2 else { return }
        
        let action = components[0]
        let resource = components[1]
        
        switch action {
        case "subscribe":
            // Handle subscription
            break
        case "unsubscribe":
            // Handle unsubscription
            break
        default:
            break
        }
    }
    
    public func broadcast(_ message: NWProtocolWebSocket.Message) {
        for connection in connections {
            connection.send(message: message, completion: .idempotent)
        }
    }
}