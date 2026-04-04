import Foundation

/// Thread-safe caching system for SLATE components
public actor Cache<Key: Hashable, Value: Codable> {
    
    public struct CacheEntry: Codable {
        public let value: Value
        public let timestamp: Date
        public let ttl: TimeInterval
        public let accessCount: Int
        public let lastAccessed: Date
        
        public init(value: Value, ttl: TimeInterval) {
            self.value = value
            self.timestamp = Date()
            self.ttl = ttl
            self.accessCount = 0
            self.lastAccessed = Date()
        }
        
        public init(value: Value, timestamp: Date, ttl: TimeInterval, accessCount: Int, lastAccessed: Date) {
            self.value = value
            self.timestamp = timestamp
            self.ttl = ttl
            self.accessCount = accessCount
            self.lastAccessed = lastAccessed
        }
        
        public var isExpired: Bool {
            return Date().timeIntervalSince(timestamp) > ttl
        }
        
        public func withAccess() -> CacheEntry {
            return CacheEntry(
                value: value,
                timestamp: timestamp,
                ttl: ttl,
                accessCount: accessCount + 1,
                lastAccessed: Date()
            )
        }
    }
    
    private var storage: [Key: CacheEntry] = [:]
    private let maxSize: Int
    private let defaultTTL: TimeInterval
    private let cleanupInterval: TimeInterval
    private var lastCleanup: Date = Date()
    
    public init(maxSize: Int = 1000, defaultTTL: TimeInterval = 3600, cleanupInterval: TimeInterval = 300) {
        self.maxSize = maxSize
        self.defaultTTL = defaultTTL
        self.cleanupInterval = cleanupInterval
    }
    
    // MARK: - Cache Operations
    
    public func get(_ key: Key) -> Value? {
        // Cleanup expired entries periodically
        if Date().timeIntervalSince(lastCleanup) > cleanupInterval {
            cleanupExpired()
        }
        
        guard var entry = storage[key] else { return nil }
        
        // Check if expired
        if entry.isExpired {
            storage.removeValue(forKey: key)
            return nil
        }
        
        // Update access info
        entry = entry.withAccess()
        storage[key] = entry
        
        return entry.value
    }
    
    public func set(_ key: Key, value: Value, ttl: TimeInterval? = nil) {
        let entry = CacheEntry(value: value, ttl: ttl ?? defaultTTL)
        
        // If cache is full, remove least recently used items
        if storage.count >= maxSize && !storage.keys.contains(key) {
            evictLRU()
        }
        
        storage[key] = entry
    }
    
    public func remove(_ key: Key) {
        storage.removeValue(forKey: key)
    }
    
    public func removeAll() {
        storage.removeAll()
    }
    
    // MARK: - Cache Statistics
    
    public var count: Int {
        return storage.count
    }
    
    public var keys: [Key] {
        return Array(storage.keys)
    }
    
    public func getEntryInfo(_ key: Key) -> CacheEntry? {
        return storage[key]
    }
    
    public func getStatistics() -> CacheStatistics {
        let entries = Array(storage.values)
        let expiredCount = entries.filter { $0.isExpired }.count
        let totalAccesses = entries.reduce(0) { $0 + $1.accessCount }
        let averageAccesses = entries.isEmpty ? 0 : Double(totalAccesses) / Double(entries.count)
        
        return CacheStatistics(
            totalEntries: entries.count,
            expiredEntries: expiredCount,
            maxEntries: maxSize,
            totalAccesses: totalAccesses,
            averageAccesses: averageAccesses,
            hitRate: 0, // Would need to track hits/misses
            memoryUsage: estimateMemoryUsage()
        )
    }
    
    // MARK: - Private Methods
    
    private func cleanupExpired() {
        let now = Date()
        storage = storage.filter { !$0.value.isExpired }
        lastCleanup = now
    }
    
    private func evictLRU() {
        guard let oldestKey = storage.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })?.key else {
            return
        }
        storage.removeValue(forKey: oldestKey)
    }
    
    private func estimateMemoryUsage() -> Int {
        // Rough estimation - in production would use more accurate calculation
        return storage.count * 1024 // Assume 1KB per entry
    }
}

public struct CacheStatistics: Codable {
    public let totalEntries: Int
    public let expiredEntries: Int
    public let maxEntries: Int
    public let totalAccesses: Int
    public let averageAccesses: Double
    public let hitRate: Double
    public let memoryUsage: Int
}

// MARK: - Specialized Caches

/// Cache for sync results
public actor SyncResultCache {
    private let cache: Cache<String, CachedSyncResult>
    private let configuration: SLATEConfiguration.CachingSettings
    
    public init(configuration: SLATEConfiguration.CachingSettings) {
        self.configuration = configuration
        self.cache = Cache(maxSize: configuration.maxSize, defaultTTL: configuration.ttl)
    }
    
    public func getSyncResult(
        primaryURL: URL,
        secondaryURL: URL,
        fps: Double
    ) -> CachedSyncResult? {
        guard configuration.enabled else { return nil }
        
        let key = makeKey(primaryURL: primaryURL, secondaryURL: secondaryURL, fps: fps)
        return cache.get(key)
    }
    
    public func setSyncResult(
        _ result: CachedSyncResult,
        primaryURL: URL,
        secondaryURL: URL,
        fps: Double
    ) {
        guard configuration.enabled else { return }
        
        let key = makeKey(primaryURL: primaryURL, secondaryURL: secondaryURL, fps: fps)
        cache.set(key, value: result, ttl: configuration.ttl)
    }
    
    private func makeKey(primaryURL: URL, secondaryURL: URL, fps: Double) -> String {
        var components = [primaryURL.path, secondaryURL.path, String(fps)]
        
        if configuration.includeChecksum {
            // Add file checksums if available
            if let primaryChecksum = try? checksumOfFile(at: primaryURL) {
                components.append(primaryChecksum)
            }
            if let secondaryChecksum = try? checksumOfFile(at: secondaryURL) {
                components.append(secondaryChecksum)
            }
        }
        
        return components.joined(separator: "|")
    }
    
    private func checksumOfFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

/// Cache for AI scores
public actor AIScoreCache {
    private let cache: Cache<String, CachedAIScores>
    private let configuration: SLATEConfiguration.CachingSettings
    
    public init(configuration: SLATEConfiguration.CachingSettings) {
        self.configuration = configuration
        self.cache = Cache(maxSize: configuration.maxSize, defaultTTL: configuration.ttl)
    }
    
    public func getAIScores(for clip: Clip) -> CachedAIScores? {
        guard configuration.enabled else { return nil }
        
        let key = makeKey(for: clip)
        return cache.get(key)
    }
    
    public func setAIScores(_ scores: CachedAIScores, for clip: Clip) {
        guard configuration.enabled else { return }
        
        let key = makeKey(for: clip)
        cache.set(key, value: scores, ttl: configuration.ttl)
    }
    
    private func makeKey(for clip: Clip) -> String {
        var components = [clip.id, clip.sourcePath, String(clip.duration)]
        
        if let proxyChecksum = clip.proxyChecksum {
            components.append(proxyChecksum)
        }
        
        if configuration.includeChecksum {
            components.append(clip.checksum)
        }
        
        return components.joined(separator: "|")
    }
}

/// Cache for model inference results
public actor ModelInferenceCache {
    private let cache: Cache<String, CachedInferenceResult>
    private let configuration: SLATEConfiguration.CachingSettings
    
    public init(configuration: SLATEConfiguration.CachingSettings) {
        self.configuration = configuration
        self.cache = Cache(maxSize: configuration.maxSize, defaultTTL: configuration.ttl)
    }
    
    public func getResult(
        model: String,
        inputHash: String
    ) -> CachedInferenceResult? {
        guard configuration.enabled else { return nil }
        
        let key = "\(model)|\(inputHash)"
        return cache.get(key)
    }
    
    public func setResult(
        _ result: CachedInferenceResult,
        model: String,
        inputHash: String
    ) {
        guard configuration.enabled else { return }
        
        let key = "\(model)|\(inputHash)"
        cache.set(key, value: result, ttl: configuration.ttl)
    }
    
    public func hashInput<T: Codable>(_ input: T) throws -> String {
        let data = try JSONEncoder().encode(input)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Cached Types

public struct CachedSyncResult: Codable {
    public let offsetFrames: Int
    public let offsetSeconds: Double
    public let confidence: SyncConfidence
    public let method: SyncMethod
    public let driftPPM: Double?
    public let processingTime: TimeInterval
    public let cachedAt: Date
    
    public init(
        offsetFrames: Int,
        offsetSeconds: Double,
        confidence: SyncConfidence,
        method: SyncMethod,
        driftPPM: Double? = nil,
        processingTime: TimeInterval,
        cachedAt: Date = Date()
    ) {
        self.offsetFrames = offsetFrames
        self.offsetSeconds = offsetSeconds
        self.confidence = confidence
        self.method = method
        self.driftPPM = driftPPM
        self.processingTime = processingTime
        self.cachedAt = cachedAt
    }
    
    public init(from result: MultiCamSyncResult, processingTime: TimeInterval) {
        self.offsetFrames = result.offsetFrames
        self.offsetSeconds = result.offsetSeconds
        self.confidence = result.confidence
        self.method = result.method
        self.driftPPM = result.driftPPM
        self.processingTime = processingTime
        self.cachedAt = Date()
    }
}

public struct CachedAIScores: Codable {
    public let scores: AIScores
    public let modelVersions: [String: String]
    public let confidences: [String: Double]
    public let processingTimes: [String: TimeInterval]
    public let cachedAt: Date
    
    public init(
        scores: AIScores,
        modelVersions: [String: String],
        confidences: [String: Double],
        processingTimes: [String: TimeInterval],
        cachedAt: Date = Date()
    ) {
        self.scores = scores
        self.modelVersions = modelVersions
        self.confidences = confidences
        self.processingTimes = processingTimes
        self.cachedAt = cachedAt
    }
}

public struct CachedInferenceResult: Codable {
    public let result: Data // Serialized result
    public let confidence: Double
    public let processingTime: TimeInterval
    public let modelVersion: String
    public let cachedAt: Date
    
    public init(
        result: Data,
        confidence: Double,
        processingTime: TimeInterval,
        modelVersion: String,
        cachedAt: Date = Date()
    ) {
        self.result = result
        self.confidence = confidence
        self.processingTime = processingTime
        self.modelVersion = modelVersion
        self.cachedAt = cachedAt
    }
}

// MARK: - Cache Manager

/// Global cache manager
public actor CacheManager {
    
    public static let shared = CacheManager()
    
    private var syncCache: SyncResultCache?
    private var aiScoreCache: AIScoreCache?
    private var modelCache: ModelInferenceCache?
    private var genericCaches: [String: Any] = [:]
    
    private init() {}
    
    public func initialize(with configuration: SLATEConfiguration) {
        self.syncCache = SyncResultCache(configuration: configuration.aiPipeline.models.caching)
        self.aiScoreCache = AIScoreCache(configuration: configuration.aiPipeline.models.caching)
        self.modelCache = ModelInferenceCache(configuration: configuration.aiPipeline.models.caching)
    }
    
    public func getSyncCache() -> SyncResultCache? {
        return syncCache
    }
    
    public func getAIScoreCache() -> AIScoreCache? {
        return aiScoreCache
    }
    
    public func getModelCache() -> ModelInferenceCache? {
        return modelCache
    }
    
    public func createGenericCache<Key: Hashable, Value: Codable>(
        name: String,
        maxSize: Int = 1000,
        ttl: TimeInterval = 3600
    ) -> Cache<Key, Value> {
        if let existing = genericCaches[name] as? Cache<Key, Value> {
            return existing
        }
        
        let newCache = Cache<Key, Value>(maxSize: maxSize, defaultTTL: ttl)
        genericCaches[name] = newCache
        return newCache
    }
    
    public func clearAllCaches() async {
        await syncCache?.cache.removeAll()
        await aiScoreCache?.cache.removeAll()
        await modelCache?.cache.removeAll()
        
        for (_, cache) in genericCaches {
            if let typedCache = cache as? any CacheProtocol {
                await typedCache.removeAll()
            }
        }
    }
    
    public func getStatistics() async -> CacheStatisticsReport {
        return CacheStatisticsReport(
            syncCache: await syncCache?.cache.getStatistics(),
            aiScoreCache: await aiScoreCache?.cache.getStatistics(),
            modelCache: await modelCache?.cache.getStatistics(),
            genericCacheCount: genericCaches.count
        )
    }
}

// MARK: - Protocols

protocol CacheProtocol {
    func removeAll() async
}

extension Cache: CacheProtocol {
    func removeAll() async {
        self.removeAll()
    }
}

public struct CacheStatisticsReport: Codable {
    public let syncCache: CacheStatistics?
    public let aiScoreCache: CacheStatistics?
    public let modelCache: CacheStatistics?
    public let genericCacheCount: Int
    
    public func generateSummary() -> String {
        var summary = "Cache Statistics Report\n"
        summary += "======================\n\n"
        
        if let sync = syncCache {
            summary += "Sync Cache:\n"
            summary += "  Entries: \(sync.totalEntries)/\(sync.maxEntries)\n"
            summary += "  Expired: \(sync.expiredEntries)\n"
            summary += "  Hit Rate: \(String(format: "%.1f", sync.hitRate * 100))%\n\n"
        }
        
        if let ai = aiScoreCache {
            summary += "AI Score Cache:\n"
            summary += "  Entries: \(ai.totalEntries)/\(ai.maxEntries)\n"
            summary += "  Expired: \(ai.expiredEntries)\n"
            summary += "  Hit Rate: \(String(format: "%.1f", ai.hitRate * 100))%\n\n"
        }
        
        if let model = modelCache {
            summary += "Model Cache:\n"
            summary += "  Entries: \(model.totalEntries)/\(model.maxEntries)\n"
            summary += "  Expired: \(model.expiredEntries)\n"
            summary += "  Hit Rate: \(String(format: "%.1f", model.hitRate * 100))%\n\n"
        }
        
        summary += "Generic Caches: \(genericCacheCount)\n"
        
        return summary
    }
}

// MARK: - SHA256 Helper

import CryptoKit

extension SHA256 {
    public static func hash(data: Data) -> [UInt8] {
        return Array(SHA256.hash(data: data))
    }
}
