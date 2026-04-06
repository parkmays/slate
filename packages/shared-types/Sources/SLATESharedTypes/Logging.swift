import Foundation
import OSLog

/// Structured logging system for SLATE components
public struct SLATELogger {
    
    public struct LogEntry: Codable, Sendable {
        public let timestamp: Date
        public let level: LogLevel
        public let category: String
        public let message: String
        public let metadata: [String: AnyCodable]
        public let error: ErrorCodable?
        
        public init(
            timestamp: Date = Date(),
            level: LogLevel,
            category: String,
            message: String,
            metadata: [String: Any] = [:],
            error: Error? = nil
        ) {
            self.timestamp = timestamp
            self.level = level
            self.category = category
            self.message = message
            self.metadata = metadata.mapValues { AnyCodable($0) }
            self.error = error.map { ErrorCodable($0) }
        }
    }
    
    public enum LogLevel: String, Codable, CaseIterable, Sendable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
    
    private let subsystem = "com.slate.ai"
    private let category: String
    private let osLog: OSLog
    private let configuration: SLATEConfiguration.Logging
    
    public init(category: String, configuration: SLATEConfiguration.Logging = .default) {
        self.category = category
        self.configuration = configuration
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }
    
    // MARK: - Logging Methods
    
    public func debug(_ message: String, metadata: [String: Any] = [:], error: Error? = nil) {
        log(.debug, message: message, metadata: metadata, error: error)
    }
    
    public func info(_ message: String, metadata: [String: Any] = [:], error: Error? = nil) {
        log(.info, message: message, metadata: metadata, error: error)
    }
    
    public func warning(_ message: String, metadata: [String: Any] = [:], error: Error? = nil) {
        log(.warning, message: message, metadata: metadata, error: error)
    }
    
    public func error(_ message: String, metadata: [String: Any] = [:], error: Error? = nil) {
        log(.error, message: message, metadata: metadata, error: error)
    }
    
    private func log(_ level: LogLevel, message: String, metadata: [String: Any], error: Error?) {
        // Check log level
        guard shouldLog(level) else { return }
        
        // Create log entry
        let entry = LogEntry(
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            error: error
        )
        
        // Log to OSLog
        if configuration.structured {
            let osMessage = formatStructuredMessage(entry)
            os_log("%{public}@", log: osLog, type: level.osLogType, osMessage)
        } else {
            let simpleMessage = formatSimpleMessage(entry)
            os_log("%{public}@", log: osLog, type: level.osLogType, simpleMessage)
        }
        
        // Log to file if configured (static helper avoids capturing `self` in a `Task` for Swift 6 sending rules)
        if !configuration.filePath.isEmpty {
            let logging = configuration
            Task {
                await Self.writeToFile(entry, logging: logging)
            }
        }
        
        // Log metrics if enabled
        if configuration.enableMetrics {
            Task {
                await MetricsManager.shared.record(entry)
            }
        }
    }
    
    private func shouldLog(_ level: LogLevel) -> Bool {
        let configLevel = Self.mapConfigLevel(configuration.level)
        let levels: [LogLevel] = [.debug, .info, .warning, .error]
        guard let configIndex = levels.firstIndex(of: configLevel),
              let messageIndex = levels.firstIndex(of: level) else {
            return true
        }
        return messageIndex >= configIndex
    }
    
    private static func mapConfigLevel(_ level: SLATEConfiguration.LogLevel) -> LogLevel {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
    
    private func formatStructuredMessage(_ entry: LogEntry) -> String {
        var parts: [String] = []
        
        // Timestamp
        let formatter = ISO8601DateFormatter()
        parts.append(formatter.string(from: entry.timestamp))
        
        // Level
        parts.append("[\(entry.level.rawValue)]")
        
        // Category
        parts.append("[\(entry.category)]")
        
        // Message
        parts.append(entry.message)
        
        // Metadata
        if !entry.metadata.isEmpty {
            let metadataString = entry.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            parts.append("(\(metadataString))")
        }
        
        // Error
        if let error = entry.error {
            parts.append("ERROR: \(error.description)")
        }
        
        return parts.joined(separator: " ")
    }
    
    private func formatSimpleMessage(_ entry: LogEntry) -> String {
        return "\(entry.level.emoji) [\(entry.category)] \(entry.message)"
    }
    
    private static func writeToFile(_ entry: LogEntry, logging: SLATEConfiguration.Logging) async {
        // Implementation would write to rotating log files
        // This is a simplified version
        guard let data = try? JSONEncoder().encode(entry),
              let string = String(data: data, encoding: .utf8) else { return }
        
        let fileURL = URL(fileURLWithPath: logging.filePath)
        
        // Check file size and rotate if necessary
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let fileSize = attributes[.size] as? Int,
           fileSize > logging.maxFileSize {
            await rotateLogFile(logging: logging)
        }
        
        // Append to file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(string.data(using: .utf8) ?? Data())
                handle.write("\n".data(using: .utf8) ?? Data())
                handle.closeFile()
            }
        } else {
            try? string.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
    
    private static func rotateLogFile(logging: SLATEConfiguration.Logging) async {
        let fileURL = URL(fileURLWithPath: logging.filePath)
        let fileManager = FileManager.default
        
        // Remove oldest file if we have too many
        for i in (1..<logging.maxFiles).reversed() {
            let oldURL = fileURL.appendingPathExtension("\(i).old")
            if fileManager.fileExists(atPath: oldURL.path) {
                try? fileManager.removeItem(at: oldURL)
            }
        }
        
        // Rotate existing files
        for i in (1..<logging.maxFiles).reversed() {
            let currentURL = fileURL.appendingPathExtension("\(i-1).old")
            let newURL = fileURL.appendingPathExtension("\(i).old")
            if fileManager.fileExists(atPath: currentURL.path) {
                try? fileManager.moveItem(at: currentURL, to: newURL)
            }
        }
        
        // Move current file
        let firstOldURL = fileURL.appendingPathExtension("0.old")
        try? fileManager.moveItem(at: fileURL, to: firstOldURL)
    }
}

// MARK: - Metrics Manager

/// Metrics collection and reporting
public actor MetricsManager {
    
    public static let shared = MetricsManager()
    
    private var performanceMetrics: [String: [PerformanceMetric]] = [:]
    private var counters: [String: Int] = [:]
    private var gauges: [String: Double] = [:]
    private var histograms: [String: Histogram] = [:]
    
    private init() {}
    
    // MARK: - Performance Metrics
    
    public func recordPerformance(
        operation: String,
        duration: TimeInterval,
        metadata: [String: Any] = [:]
    ) {
        let metric = PerformanceMetric(
            timestamp: Date(),
            duration: duration,
            metadata: metadata
        )
        
        performanceMetrics[operation, default: []].append(metric)
        
        // Keep only recent metrics (last 1000)
        if let metrics = performanceMetrics[operation],
           metrics.count > 1000 {
            performanceMetrics[operation] = Array(metrics.suffix(1000))
        }
    }
    
    public func getAveragePerformance(for operation: String, since date: Date? = nil) -> TimeInterval? {
        guard let metrics = performanceMetrics[operation],
              !metrics.isEmpty else { return nil }
        
        let filtered = date == nil ? metrics : metrics.filter { $0.timestamp >= date! }
        guard !filtered.isEmpty else { return nil }
        
        return filtered.reduce(0) { $0 + $1.duration } / Double(filtered.count)
    }
    
    // MARK: - Counters
    
    public func incrementCounter(_ name: String, by value: Int = 1) {
        counters[name, default: 0] += value
    }
    
    public func getCounter(_ name: String) -> Int {
        return counters[name] ?? 0
    }
    
    // MARK: - Gauges
    
    public func setGauge(_ name: String, value: Double) {
        gauges[name] = value
    }
    
    public func getGauge(_ name: String) -> Double? {
        return gauges[name]
    }
    
    // MARK: - Histograms
    
    public func recordHistogram(_ name: String, value: Double) {
        histograms[name, default: Histogram()].record(value)
    }
    
    public func getHistogram(_ name: String) -> Histogram? {
        return histograms[name]
    }
    
    // MARK: - Reporting
    
    public func generateReport() -> MetricsReport {
        return MetricsReport(
            timestamp: Date(),
            performanceMetrics: performanceMetrics.mapValues { metrics in
                PerformanceReport(
                    count: metrics.count,
                    averageDuration: metrics.reduce(0) { $0 + $1.duration } / Double(metrics.count),
                    minDuration: metrics.map(\.duration).min() ?? 0,
                    maxDuration: metrics.map(\.duration).max() ?? 0,
                    p95Duration: calculatePercentile(metrics.map(\.duration), 0.95),
                    p99Duration: calculatePercentile(metrics.map(\.duration), 0.99)
                )
            },
            counters: counters,
            gauges: gauges,
            histograms: histograms.mapValues { $0 }
        )
    }
    
    private func calculatePercentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * percentile)
        return sorted[min(index, sorted.count - 1)]
    }
    
    // MARK: - Log Entry Recording
    
    func record(_ entry: SLATELogger.LogEntry) {
        // Extract metrics from log entries
        switch entry.category {
        case "SyncEngine":
            if let duration = entry.metadata["duration"]?.value as? TimeInterval {
                recordPerformance(
                    operation: "sync",
                    duration: duration,
                    metadata: entry.metadata.mapValues { $0.value }
                )
            }
            if let confidence = entry.metadata["confidence"]?.value as? Double {
                recordHistogram("sync_confidence", value: confidence)
            }
            
        case "AIPipeline":
            if let operation = entry.metadata["operation"]?.value as? String,
               let duration = entry.metadata["duration"]?.value as? TimeInterval {
                recordPerformance(
                    operation: "ai_\(operation)",
                    duration: duration,
                    metadata: entry.metadata.mapValues { $0.value }
                )
            }
            
        default:
            break
        }
        
        // Count log levels
        incrementCounter("logs_\(entry.level.rawValue.lowercased())")
    }
}

// MARK: - Supporting Types

public struct PerformanceMetric: Codable, Sendable {
    public let timestamp: Date
    public let duration: TimeInterval
    public let metadata: [String: AnyCodable]
    
    public init(timestamp: Date, duration: TimeInterval, metadata: [String: Any]) {
        self.timestamp = timestamp
        self.duration = duration
        self.metadata = metadata.mapValues { AnyCodable($0) }
    }
}

public struct Histogram: Codable, Sendable {
    private var buckets: [Double: Int] = [:]
    private var count: Int = 0
    private var sum: Double = 0
    private var min: Double = Double.infinity
    private var max: Double = -Double.infinity
    
    public init() {}
    
    public mutating func record(_ value: Double) {
        // Simple bucketing - in production would use more sophisticated histogram
        let bucket = (value * 100).rounded() / 100 // 2 decimal places
        buckets[bucket, default: 0] += 1
        
        count += 1
        sum += value
        min = Swift.min(min, value)
        max = Swift.max(max, value)
    }
    
    public var average: Double {
        return count > 0 ? sum / Double(count) : 0
    }
    
    public var countValue: Int {
        return count
    }
    
    public var minValue: Double {
        return min == Double.infinity ? 0 : min
    }
    
    public var maxValue: Double {
        return max == -Double.infinity ? 0 : max
    }
}

public struct PerformanceReport: Codable, Sendable {
    public let count: Int
    public let averageDuration: TimeInterval
    public let minDuration: TimeInterval
    public let maxDuration: TimeInterval
    public let p95Duration: TimeInterval
    public let p99Duration: TimeInterval
}

public struct MetricsReport: Codable, Sendable {
    public let timestamp: Date
    public let performanceMetrics: [String: PerformanceReport]
    public let counters: [String: Int]
    public let gauges: [String: Double]
    public let histograms: [String: Histogram]
    
    public func generateSummary() -> String {
        var summary = "SLATE Metrics Report\n"
        summary += "===================\n\n"
        summary += "Generated: \(timestamp)\n\n"
        
        // Performance metrics
        if !performanceMetrics.isEmpty {
            summary += "Performance Metrics:\n"
            for (operation, report) in performanceMetrics.sorted(by: { $0.key < $1.key }) {
                summary += "  \(operation):\n"
                summary += "    Count: \(report.count)\n"
                summary += "    Average: \(String(format: "%.3f", report.averageDuration))s\n"
                summary += "    Min: \(String(format: "%.3f", report.minDuration))s\n"
                summary += "    Max: \(String(format: "%.3f", report.maxDuration))s\n"
                summary += "    P95: \(String(format: "%.3f", report.p95Duration))s\n"
                summary += "    P99: \(String(format: "%.3f", report.p99Duration))s\n\n"
            }
        }
        
        // Counters
        if !counters.isEmpty {
            summary += "Counters:\n"
            for (name, value) in counters.sorted(by: { $0.key < $1.key }) {
                summary += "  \(name): \(value)\n"
            }
            summary += "\n"
        }
        
        // Gauges
        if !gauges.isEmpty {
            summary += "Gauges:\n"
            for (name, value) in gauges.sorted(by: { $0.key < $1.key }) {
                summary += "  \(name): \(String(format: "%.2f", value))\n"
            }
            summary += "\n"
        }
        
        return summary
    }
}

// MARK: - Codable Wrappers

public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else {
            value = NSNull()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else {
            try container.encodeNil()
        }
    }
}

public struct ErrorCodable: Codable, Sendable {
    public let description: String
    
    public init(_ error: Error) {
        self.description = error.localizedDescription
    }
}
