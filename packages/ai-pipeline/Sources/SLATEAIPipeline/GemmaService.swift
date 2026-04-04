import Foundation
import SLATESharedTypes

struct GemmaPerformanceInsightRequest: Codable, Sendable {
    struct Metrics: Codable, Sendable {
        let totalDuration: Double
        let speechCoverage: Double
        let averagePhraseDuration: Double
        let averagePauseDuration: Double
        let phraseDurationVariance: Double
        let wordsPerSecond: Double
    }

    let transcriptText: String
    let transcriptLanguage: String?
    let scriptText: String
    let heuristicScore: Double
    let wordCount: Int
    let metrics: Metrics
}

struct GemmaPerformanceInsightResponse: Codable, Sendable {
    struct Reason: Codable, Sendable {
        let dimension: String?
        let score: Double?
        let flag: String
        let message: String
        let timecode: String?
    }

    let modelVersion: String
    let score: Double?
    let reasons: [Reason]
}

private struct GemmaHealthResponse: Codable {
    let ok: Bool
}

private struct GemmaErrorResponse: Codable {
    let error: String
}

private struct GemmaServiceError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

actor GemmaService {
    static let shared = GemmaService()

    struct Configuration: Sendable {
        let enabled: Bool
        let modelID: String
        let host: String
        let port: Int
        let pythonExecutable: String
        let enableThinking: Bool
        let maxNewTokens: Int
        let requestTimeout: TimeInterval
        let startupTimeout: TimeInterval
        let autostart: Bool

        var baseURL: URL {
            URL(string: "http://\(host):\(port)")!
        }

        static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
            Self(
                enabled: parseBoolean(environment["SLATE_GEMMA_ENABLED"], defaultValue: false),
                modelID: environment["SLATE_GEMMA_MODEL_ID"] ?? "google/gemma-4-E2B-it",
                host: environment["SLATE_GEMMA_HOST"] ?? "127.0.0.1",
                port: Int(environment["SLATE_GEMMA_PORT"] ?? "") ?? 8797,
                pythonExecutable: environment["SLATE_GEMMA_PYTHON_EXECUTABLE"] ?? "python3",
                enableThinking: parseBoolean(environment["SLATE_GEMMA_ENABLE_THINKING"], defaultValue: false),
                maxNewTokens: Int(environment["SLATE_GEMMA_MAX_NEW_TOKENS"] ?? "") ?? 384,
                requestTimeout: TimeInterval(Int(environment["SLATE_GEMMA_REQUEST_TIMEOUT"] ?? "") ?? 300),
                startupTimeout: TimeInterval(Int(environment["SLATE_GEMMA_STARTUP_TIMEOUT"] ?? "") ?? 25),
                autostart: parseBoolean(environment["SLATE_GEMMA_AUTOSTART"], defaultValue: true)
            )
        }

        var bridgeEnvironment: [String: String] {
            [
                "PYTHONUNBUFFERED": "1",
                "SLATE_GEMMA_MODEL_ID": modelID,
                "SLATE_GEMMA_HOST": host,
                "SLATE_GEMMA_PORT": String(port),
                "SLATE_GEMMA_ENABLE_THINKING": enableThinking ? "1" : "0",
                "SLATE_GEMMA_MAX_NEW_TOKENS": String(maxNewTokens)
            ]
        }

        private static func parseBoolean(_ rawValue: String?, defaultValue: Bool) -> Bool {
            guard let rawValue else { return defaultValue }

            switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return defaultValue
            }
        }
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    func performanceInsight(
        for request: GemmaPerformanceInsightRequest
    ) async throws -> GemmaPerformanceInsightResponse? {
        let configuration = Configuration.current()
        guard configuration.enabled else {
            return nil
        }

        try await ensureServerIsReachable(configuration: configuration)
        return try await postPerformanceInsight(request, configuration: configuration)
    }

    private func ensureServerIsReachable(configuration: Configuration) async throws {
        if try await healthCheck(configuration: configuration) {
            return
        }

        guard configuration.autostart else {
            throw GemmaServiceError(message: "Gemma is enabled, but no helper is listening at \(configuration.baseURL.absoluteString).")
        }

        try launchBridgeIfNeeded(configuration: configuration)
        try await waitForHealthyBridge(configuration: configuration)
    }

    private func launchBridgeIfNeeded(configuration: Configuration) throws {
        if let process, process.isRunning {
            return
        }

        guard let scriptURL = Bundle.module.url(forResource: "gemma_bridge", withExtension: "py") else {
            throw GemmaServiceError(message: "The bundled Gemma bridge resource is missing from SLATEAIPipeline.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [configuration.pythonExecutable, scriptURL.path]

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.bridgeEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GemmaServiceError(
                message: "Unable to launch the Gemma helper with \(configuration.pythonExecutable): \(error.localizedDescription)"
            )
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    private func waitForHealthyBridge(configuration: Configuration) async throws {
        let deadline = Date().addingTimeInterval(configuration.startupTimeout)

        while Date() < deadline {
            if try await healthCheck(configuration: configuration) {
                return
            }

            if let process, !process.isRunning {
                throw GemmaServiceError(message: terminatedProcessMessage(prefix: "Gemma helper exited during startup"))
            }

            try await Task.sleep(nanoseconds: 250_000_000)
        }

        throw GemmaServiceError(
            message: "Timed out waiting for the Gemma helper to start at \(configuration.baseURL.absoluteString)."
        )
    }

    private func healthCheck(configuration: Configuration) async throws -> Bool {
        var request = URLRequest(url: configuration.baseURL.appending(path: "health"))
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }

            if let payload = try? JSONDecoder().decode(GemmaHealthResponse.self, from: data) {
                return payload.ok
            }
            return true
        } catch {
            return false
        }
    }

    private func postPerformanceInsight(
        _ payload: GemmaPerformanceInsightRequest,
        configuration: Configuration
    ) async throws -> GemmaPerformanceInsightResponse {
        var request = URLRequest(url: configuration.baseURL.appending(path: "v1/performance-insight"))
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GemmaServiceError(message: "Gemma helper returned a non-HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorPayload = try? JSONDecoder().decode(GemmaErrorResponse.self, from: data) {
                throw GemmaServiceError(message: errorPayload.error)
            }

            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GemmaServiceError(
                message: "Gemma helper request failed with HTTP \(httpResponse.statusCode)\(body.map { ": \($0)" } ?? "")."
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GemmaPerformanceInsightResponse.self, from: data)
    }

    private func terminatedProcessMessage(prefix: String) -> String {
        let stdout = stdoutPipe?.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe?.fileHandleForReading.readDataToEndOfFile()
        let combined = [stderr, stdout]
            .compactMap { $0 }
            .compactMap { data in
                String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first(where: { !$0.isEmpty })

        return combined.map { "\(prefix): \($0)" } ?? prefix
    }
}
