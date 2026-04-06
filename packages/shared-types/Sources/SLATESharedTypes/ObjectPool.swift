import Foundation
import Accelerate
import CoreGraphics
import CoreML

/// Holds a pooled `vImage_Buffer` (reference type wrapper for `ObjectPool`).
public final class VImageBufferBox: NSObject {
    public var buffer: vImage_Buffer
    
    public init(buffer: vImage_Buffer) {
        self.buffer = buffer
        super.init()
    }
}

/// Holds pooled FFT setup (reference type wrapper for `ObjectPool`).
public final class FFTSetupBox: NSObject {
    public let setup: FFTSetup
    
    public init(setup: FFTSetup) {
        self.setup = setup
        super.init()
    }
}

/// Generic object pool for memory-efficient reuse of expensive objects
public final class ObjectPool<T: AnyObject> {
    private let lock = NSRecursiveLock()
    
    private var available: [T] = []
    private var inUse: Set<ObjectIdentifier> = []
    private let factory: () -> T
    private let reset: ((T) -> Void)?
    private let maxSize: Int
    private let maxAge: TimeInterval?
    
    private var createdCount = 0
    private var reuseCount = 0
    private var creationTimestamps: [ObjectIdentifier: Date] = [:]
    
    public init(
        maxSize: Int = 100,
        maxAge: TimeInterval? = nil,
        factory: @escaping () -> T,
        reset: ((T) -> Void)? = nil
    ) {
        self.maxSize = maxSize
        self.maxAge = maxAge
        self.factory = factory
        self.reset = reset
    }
    
    // MARK: - Pool Operations
    
    public func acquire() -> T {
        lock.lock()
        defer { lock.unlock() }
        // Clean up old objects if needed
        if let maxAge = maxAge {
            cleanupOldObjects(olderThan: maxAge)
        }
        
        // Get object from pool or create new
        let object: T
        if !available.isEmpty {
            object = available.removeLast()
            reuseCount += 1
        } else {
            object = factory()
            createdCount += 1
        }
        
        // Track usage
        let id = ObjectIdentifier(object)
        inUse.insert(id)
        creationTimestamps[id] = Date()
        
        return object
    }
    
    public func release(_ object: T) {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(object)
        
        // Verify object was from this pool
        guard inUse.remove(id) != nil else { return }
        
        // Reset object if needed
        reset?(object)
        
        // Return to pool if not at capacity
        if available.count < maxSize {
            available.append(object)
        } else {
            // Pool is full, let object be deallocated
            creationTimestamps.removeValue(forKey: id)
        }
    }
    
    public func with<R>(_ body: (T) throws -> R) rethrows -> R {
        let object = acquire()
        defer { release(object) }
        return try body(object)
    }
    
    // MARK: - Statistics
    
    public var statistics: PoolStatistics {
        lock.lock()
        defer { lock.unlock() }
        return PoolStatistics(
            availableCount: available.count,
            inUseCount: inUse.count,
            createdCount: createdCount,
            reuseCount: reuseCount,
            reuseRate: createdCount > 0 ? Double(reuseCount) / Double(createdCount) : 0,
            maxSize: maxSize
        )
    }
    
    // MARK: - Private Methods
    
    private func cleanupOldObjects(olderThan maxAge: TimeInterval) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-maxAge)
        
        // Remove old objects from available pool
        available.removeAll { object in
            let id = ObjectIdentifier(object)
            if let timestamp = creationTimestamps[id],
               timestamp < cutoff {
                creationTimestamps.removeValue(forKey: id)
                return true
            }
            return false
        }
        
        // Also clean up timestamps for objects no longer in pool
        creationTimestamps = creationTimestamps.filter { id, _ in
            inUse.contains(id) || available.contains(where: { ObjectIdentifier($0) == id })
        }
    }
}

public struct PoolStatistics: Sendable {
    public let availableCount: Int
    public let inUseCount: Int
    public let createdCount: Int
    public let reuseCount: Int
    public let reuseRate: Double
    public let maxSize: Int
}

// MARK: - Specialized Pools

/// Pool for audio buffers
public actor AudioBufferPool {
    
    private let pools: [Int: ObjectPool<NSMutableArray>]
    private let maxBufferSize: Int
    
    public init(maxBufferSize: Int = 1_000_000, maxPoolSize: Int = 50) {
        self.maxBufferSize = maxBufferSize
        
        // Create pools for common buffer sizes
        let commonSizes = [1024, 4096, 16384, 65536, 262144, 1048576]
        var pools: [Int: ObjectPool<NSMutableArray>] = [:]
        
        for size in commonSizes where size <= maxBufferSize {
            pools[size] = ObjectPool(
                maxSize: maxPoolSize,
                factory: { NSMutableArray(capacity: size) },
                reset: { $0.removeAllObjects() }
            )
        }
        
        self.pools = pools
    }
    
    public func getBuffer(size: Int) -> [Float] {
        // Find appropriate pool
        let poolSize = pools.keys.sorted().first { $0 >= size } ?? maxBufferSize
        
        guard let pool = pools[poolSize] else {
            // Fallback to direct allocation
            return Array(repeating: 0.0, count: size)
        }
        
        let nsArray = pool.acquire()
        defer { pool.release(nsArray) }
        
        // Ensure array is correct size
        if nsArray.count < size {
            nsArray.addObjects(from: Array(repeating: 0.0, count: size - nsArray.count))
        }
        
        // Convert to Swift array
        var result = [Float](repeating: 0.0, count: size)
        for i in 0..<size {
            if i < nsArray.count {
                result[i] = nsArray.object(at: i) as? Float ?? 0.0
            }
        }
        
        return result
    }
    
    public func getStatistics() -> [Int: PoolStatistics] {
        return pools.mapValues { $0.statistics }
    }
}

/// Pool for image buffers
public actor ImageBufferPool {
    
    private let pools: [String: ObjectPool<VImageBufferBox>]
    private let maxImageSize: CGSize
    
    public init(maxImageSize: CGSize = CGSize(width: 4096, height: 4096), maxPoolSize: Int = 20) {
        self.maxImageSize = maxImageSize
        
        // Create pools for common image sizes
        let commonSizes = [
            "320x240", "640x360", "640x480", "1280x720",
            "1920x1080", "2560x1440", "3840x2160"
        ]
        
        var pools: [String: ObjectPool<VImageBufferBox>] = [:]
        
        for sizeString in commonSizes {
            let components = sizeString.split(separator: "x").compactMap { Int($0) }
            guard components.count == 2 else { continue }
            
            let size = CGSize(width: components[0], height: components[1])
            if size.width > maxImageSize.width || size.height > maxImageSize.height {
                continue
            }
            
            pools[sizeString] = ObjectPool<VImageBufferBox>(
                maxSize: maxPoolSize,
                factory: { VImageBufferBox(buffer: Self.createImageBuffer(size: size)) },
                reset: { box in
                    if let data = box.buffer.data {
                        data.deallocate()
                    }
                }
            )
        }
        
        self.pools = pools
    }
    
    public func getBuffer(size: CGSize) -> VImageBufferBox? {
        let sizeString = "\(Int(size.width))x\(Int(size.height))"
        
        guard let pool = pools[sizeString] else {
            return VImageBufferBox(buffer: Self.createImageBuffer(size: size))
        }
        
        return pool.acquire()
    }
    
    public func releaseBuffer(_ box: VImageBufferBox, size: CGSize) {
        let sizeString = "\(Int(size.width))x\(Int(size.height))"
        
        guard let pool = pools[sizeString] else {
            if let data = box.buffer.data {
                data.deallocate()
            }
            return
        }
        
        pool.release(box)
    }
    
    public func withBuffer<R>(size: CGSize, _ body: (vImage_Buffer?) throws -> R) rethrows -> R {
        let box = getBuffer(size: size)
        defer {
            if let box {
                releaseBuffer(box, size: size)
            }
        }
        return try body(box?.buffer)
    }
    
    private static func createImageBuffer(size: CGSize) -> vImage_Buffer {
        var buffer = vImage_Buffer()
        let bytesPerPixel = 4 // RGBA
        let rowBytes = Int(size.width) * bytesPerPixel
        let totalBytes = rowBytes * Int(size.height)
        
        buffer.data = UnsafeMutableRawPointer.allocate(byteCount: totalBytes, alignment: 4)
        buffer.height = vImagePixelCount(size.height)
        buffer.width = vImagePixelCount(size.width)
        buffer.rowBytes = rowBytes
        
        return buffer
    }
    
    public func getStatistics() -> [String: PoolStatistics] {
        return pools.mapValues { $0.statistics }
    }
}

/// Pool for FFT buffers
public actor FFTBufferPool {
    
    private let pools: [Int: ObjectPool<FFTSetupBox>]
    private let maxFFTSize: Int
    
    public init(maxFFTSize: Int = 65536, maxPoolSize: Int = 10) {
        self.maxFFTSize = maxFFTSize
        
        // Create pools for common FFT sizes (powers of 2)
        let commonSizes = [256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536]
        var pools: [Int: ObjectPool<FFTSetupBox>] = [:]
        
        for size in commonSizes where size <= maxFFTSize {
            pools[size] = ObjectPool<FFTSetupBox>(
                maxSize: maxPoolSize,
                factory: {
                    guard let setup = Self.createFFTSetup(size: size) else {
                        fatalError("Failed to create FFT setup for size \(size)")
                    }
                    return FFTSetupBox(setup: setup)
                },
                reset: { _ in
                    // FFTSetup doesn't need explicit reset
                }
            )
        }
        
        self.pools = pools
    }
    
    public func getSetup(size: Int) -> FFTSetupBox? {
        // Find next power of 2
        let fftSize = 1 << Int(ceil(log2(Double(size))))
        
        guard let pool = pools[fftSize] else {
            guard let setup = Self.createFFTSetup(size: fftSize) else { return nil }
            return FFTSetupBox(setup: setup)
        }
        
        return pool.acquire()
    }
    
    public func releaseSetup(_ box: FFTSetupBox, size: Int) {
        let fftSize = 1 << Int(ceil(log2(Double(size))))
        
        guard let pool = pools[fftSize] else {
            vDSP_destroy_fftsetup(box.setup)
            return
        }
        
        pool.release(box)
    }
    
    public func withSetup<R>(size: Int, _ body: (FFTSetup?) throws -> R) rethrows -> R {
        let box = getSetup(size: size)
        defer {
            if let box {
                releaseSetup(box, size: size)
            }
        }
        return try body(box?.setup)
    }
    
    private static func createFFTSetup(size: Int) -> FFTSetup? {
        let log2Size = Int(log2(Double(size)))
        return vDSP_create_fftsetup(vDSP_Length(log2Size), FFTRadix(kFFTRadix2))
    }
    
    public func getStatistics() -> [Int: PoolStatistics] {
        return pools.mapValues { $0.statistics }
    }
}

/// Pool for ML model input/output buffers
public actor MLBufferPool {
    
    private let inputPool: ObjectPool<MLMultiArray>
    private let outputPool: ObjectPool<MLMultiArray>
    
    public init(inputShape: [NSNumber], outputShape: [NSNumber], maxPoolSize: Int = 10) {
        self.inputPool = ObjectPool(
            maxSize: maxPoolSize,
            factory: { try! MLMultiArray(shape: inputShape, dataType: .float32) },
            reset: { array in
                // Zero out the array
                let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
                pointer.initialize(repeating: 0.0, count: array.count)
            }
        )
        
        self.outputPool = ObjectPool(
            maxSize: maxPoolSize,
            factory: { try! MLMultiArray(shape: outputShape, dataType: .float32) },
            reset: { array in
                let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
                pointer.initialize(repeating: 0.0, count: array.count)
            }
        )
    }
    
    public func getInputBuffer() -> MLMultiArray {
        return inputPool.acquire()
    }
    
    public func releaseInputBuffer(_ buffer: MLMultiArray) {
        inputPool.release(buffer)
    }
    
    public func getOutputBuffer() -> MLMultiArray {
        return outputPool.acquire()
    }
    
    public func releaseOutputBuffer(_ buffer: MLMultiArray) {
        outputPool.release(buffer)
    }
    
    public func withBuffers<R>(
        _ body: (MLMultiArray, MLMultiArray) throws -> R
    ) rethrows -> R {
        let input = getInputBuffer()
        let output = getOutputBuffer()
        defer {
            releaseInputBuffer(input)
            releaseOutputBuffer(output)
        }
        return try body(input, output)
    }
    
    public func getStatistics() -> (input: PoolStatistics, output: PoolStatistics) {
        return (input: inputPool.statistics, output: outputPool.statistics)
    }
}

// MARK: - Pool Manager

/// Global pool manager
public actor PoolManager {
    
    public static let shared = PoolManager()
    
    private var audioBufferPool: AudioBufferPool?
    private var imageBufferPool: ImageBufferPool?
    private var fftBufferPool: FFTBufferPool?
    private var mlBufferPools: [String: MLBufferPool] = [:]
    private var genericPools: [String: Any] = [:]
    
    private init() {}
    
    public func initialize(configuration: SLATEConfiguration) {
        self.audioBufferPool = AudioBufferPool(
            maxBufferSize: configuration.syncEngine.performance.streamingMemoryLimit,
            maxPoolSize: 20
        )
        
        self.imageBufferPool = ImageBufferPool(
            maxImageSize: CGSize(width: 4096, height: 2160),
            maxPoolSize: 10
        )
        
        self.fftBufferPool = FFTBufferPool(
            maxFFTSize: 65536,
            maxPoolSize: 5
        )
    }
    
    public func getAudioBufferPool() -> AudioBufferPool? {
        return audioBufferPool
    }
    
    public func getImageBufferPool() -> ImageBufferPool? {
        return imageBufferPool
    }
    
    public func getFFTBufferPool() -> FFTBufferPool? {
        return fftBufferPool
    }
    
    public func getMLBufferPool(
        name: String,
        inputShape: [NSNumber],
        outputShape: [NSNumber]
    ) -> MLBufferPool {
        if let existing = mlBufferPools[name] {
            return existing
        }
        
        let newPool = MLBufferPool(inputShape: inputShape, outputShape: outputShape)
        mlBufferPools[name] = newPool
        return newPool
    }
    
    public func createGenericPool<T: AnyObject>(
        name: String,
        maxSize: Int = 100,
        factory: @escaping () -> T,
        reset: ((T) -> Void)? = nil
    ) -> ObjectPool<T> {
        if let existing = genericPools[name] as? ObjectPool<T> {
            return existing
        }
        
        let newPool = ObjectPool(
            maxSize: maxSize,
            factory: factory,
            reset: reset
        )
        genericPools[name] = newPool
        return newPool
    }
    
    public func getStatistics() async -> PoolStatisticsReport {
        var mlBuffers: [String: (input: PoolStatistics, output: PoolStatistics)] = [:]
        for (name, pool) in mlBufferPools {
            mlBuffers[name] = await pool.getStatistics()
        }
        return PoolStatisticsReport(
            audioBuffers: await audioBufferPool?.getStatistics(),
            imageBuffers: await imageBufferPool?.getStatistics(),
            fftBuffers: await fftBufferPool?.getStatistics(),
            mlBuffers: mlBuffers,
            genericPoolCount: genericPools.count
        )
    }
    
    public func clearAllPools() async {
        // Clear all pools by creating new ones
        _ = await audioBufferPool?.getBuffer(size: 1024)
        await imageBufferPool?.withBuffer(size: CGSize(width: 100, height: 100)) { _ in }
        await fftBufferPool?.withSetup(size: 256) { _ in }
        
        // Generic pools would need to be cleared individually
    }
}

public struct PoolStatisticsReport: Sendable {
    public let audioBuffers: [Int: PoolStatistics]?
    public let imageBuffers: [String: PoolStatistics]?
    public let fftBuffers: [Int: PoolStatistics]?
    public let mlBuffers: [String: (input: PoolStatistics, output: PoolStatistics)]
    public let genericPoolCount: Int
    
    public func generateSummary() -> String {
        var summary = "Object Pool Statistics\n"
        summary += "======================\n\n"
        
        if let audio = audioBuffers {
            summary += "Audio Buffer Pools:\n"
            for (size, stats) in audio.sorted(by: { $0.key < $1.key }) {
                summary += "  Size \(size): \(stats.availableCount) available, \(stats.inUseCount) in use\n"
                summary += "    Reuse Rate: \(String(format: "%.1f", stats.reuseRate * 100))%\n"
            }
            summary += "\n"
        }
        
        if let image = imageBuffers {
            summary += "Image Buffer Pools:\n"
            for (size, stats) in image.sorted(by: { $0.key < $1.key }) {
                summary += "  Size \(size): \(stats.availableCount) available, \(stats.inUseCount) in use\n"
                summary += "    Reuse Rate: \(String(format: "%.1f", stats.reuseRate * 100))%\n"
            }
            summary += "\n"
        }
        
        if let fft = fftBuffers {
            summary += "FFT Buffer Pools:\n"
            for (size, stats) in fft.sorted(by: { $0.key < $1.key }) {
                summary += "  Size \(size): \(stats.availableCount) available, \(stats.inUseCount) in use\n"
                summary += "    Reuse Rate: \(String(format: "%.1f", stats.reuseRate * 100))%\n"
            }
            summary += "\n"
        }
        
        summary += "ML Buffer Pools: \(mlBuffers.count)\n"
        summary += "Generic Pools: \(genericPoolCount)\n"
        
        return summary
    }
}
