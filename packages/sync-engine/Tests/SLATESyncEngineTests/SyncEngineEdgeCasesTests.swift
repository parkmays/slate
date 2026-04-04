import Foundation
import XCTest
import SLATESyncEngine

/// Comprehensive edge case testing for SyncEngine
class SyncEngineEdgeCasesTests: XCTestCase {
    
    private var syncEngine: SyncEngine!
    private let testAudioDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("SyncEdgeCaseTests")
    
    override func setUp() async throws {
        try await super.setUp()
        syncEngine = SyncEngine()
        
        // Create test directory
        try FileManager.default.createDirectory(at: testAudioDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up test files
        try? FileManager.default.removeItem(at: testAudioDirectory)
        try await super.tearDown()
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyAudioFiles() async throws {
        let emptyURL = try generateSilentAudio(duration: 0.1)
        
        do {
            _ = try await syncEngine.syncClip(
                primary: emptyURL,
                secondary: emptyURL,
                fps: 24,
                useSlateDetection: false
            )
            XCTFail("Should have thrown an error for empty audio")
        } catch {
            // Expected
            XCTAssertTrue(error.localizedDescription.contains("empty") || 
                         error.localizedDescription.contains("duration"))
        }
    }
    
    func testVeryShortAudioFiles() async throws {
        let shortURL = try generateSilentAudio(duration: 0.5)
        
        do {
            _ = try await syncEngine.syncClip(
                primary: shortURL,
                secondary: shortURL,
                fps: 24,
                useSlateDetection: false
            )
            XCTFail("Should have thrown an error for very short audio")
        } catch {
            // Expected
        }
    }
    
    func testDifferentSampleRates() async throws {
        let primaryURL = try generateTestAudio(sampleRate: 48000, duration: 10)
        let secondaryURL = try generateTestAudio(sampleRate: 44100, duration: 10)
        
        let result = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 24,
            useSlateDetection: false
        )
        
        // Should handle different sample rates gracefully
        XCTAssertNotNil(result)
        XCTAssertEqual(result.confidence, .low) // Expected lower confidence with different sample rates
    }
    
    func testHighlyNoisyAudio() async throws {
        let noisyURL = try generateNoisyAudio(duration: 30, noiseLevel: 0.8)
        let cleanURL = try generateTestAudio(sampleRate: 48000, duration: 30)
        
        let result = try await syncEngine.syncClip(
            primary: cleanURL,
            secondary: noisyURL,
            fps: 24,
            useSlateDetection: false
        )
        
        // Should still attempt sync but with low confidence
        XCTAssertNotNil(result)
        XCTAssertEqual(result.confidence, .low)
    }
    
    func testAudioWithGaps() async throws {
        let gappedURL = try generateAudioWithGaps(duration: 30, gapDuration: 2.0)
        let continuousURL = try generateTestAudio(sampleRate: 48000, duration: 30)
        
        let result = try await syncEngine.syncClip(
            primary: continuousURL,
            secondary: gappedURL,
            fps: 24,
            useSlateDetection: false
        )
        
        // Should handle gaps gracefully
        XCTAssertNotNil(result)
    }
    
    func testVeryLargeOffset() async throws {
        let primaryURL = try generateTestAudio(sampleRate: 48000, duration: 60)
        let secondaryURL = try generateTestAudio(sampleRate: 48000, duration: 60, offset: 30.0)
        
        let result = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 24,
            useSlateDetection: false
        )
        
        // Should detect large offset
        XCTAssertNotNil(result)
        XCTAssertEqual(result.confidence, .low) // Large offsets have lower confidence
    }
    
    func testNonexistentFile() async throws {
        let primaryURL = testAudioDirectory.appendingPathComponent("nonexistent.wav")
        let secondaryURL = try generateTestAudio(sampleRate: 48000, duration: 10)
        
        do {
            _ = try await syncEngine.syncClip(
                primary: primaryURL,
                secondary: secondaryURL,
                fps: 24,
                useSlateDetection: false
            )
            XCTFail("Should have thrown an error for nonexistent file")
        } catch {
            // Expected
        }
    }
    
    func testCorruptedAudioFile() async throws {
        let corruptedURL = testAudioDirectory.appendingPathComponent("corrupted.wav")
        let corruptedData = Data([0x52, 0x49, 0x46, 0x46] + Array(repeating: 0, count: 100))
        try corruptedData.write(to: corruptedURL)
        
        let validURL = try generateTestAudio(sampleRate: 48000, duration: 10)
        
        do {
            _ = try await syncEngine.syncClip(
                primary: validURL,
                secondary: corruptedURL,
                fps: 24,
                useSlateDetection: false
            )
            XCTFail("Should have thrown an error for corrupted file")
        } catch {
            // Expected
        }
    }
    
    func testExtremeFrameRates() async throws {
        let primaryURL = try generateTestAudio(sampleRate: 48000, duration: 10)
        let secondaryURL = try generateTestAudio(sampleRate: 48000, duration: 10, offset: 1.0/120)
        
        // Test with very high frame rate
        let resultHigh = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 120,
            useSlateDetection: false
        )
        
        XCTAssertNotNil(resultHigh)
        
        // Test with very low frame rate
        let resultLow = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 12,
            useSlateDetection: false
        )
        
        XCTAssertNotNil(resultLow)
    }
    
    func testMultipleSyncAttempts() async throws {
        let primaryURL = try generateTestAudio(sampleRate: 48000, duration: 30)
        let secondaryURL = try generateTestAudio(sampleRate: 48000, duration: 30, offset: 2.0/24)
        
        // Run sync multiple times
        var results: [MultiCamSyncResult] = []
        for _ in 0..<10 {
            let result = try await syncEngine.syncClip(
                primary: primaryURL,
                secondary: secondaryURL,
                fps: 24,
                useSlateDetection: false
            )
            results.append(result)
        }
        
        // Results should be consistent
        let firstResult = results.first!
        for result in results {
            XCTAssertEqual(result.offsetFrames, firstResult.offsetFrames)
            XCTAssertEqual(result.confidence, firstResult.confidence)
        }
    }
    
    func testConcurrentSyncRequests() async throws {
        let primaryURL = try generateTestAudio(sampleRate: 48000, duration: 30)
        let secondaryURL = try generateTestAudio(sampleRate: 48000, duration: 30, offset: 1.0/24)
        
        // Run multiple sync operations concurrently
        let results = try await withThrowingTaskGroup(of: MultiCamSyncResult.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try await self.syncEngine.syncClip(
                        primary: primaryURL,
                        secondary: secondaryURL,
                        fps: 24,
                        useSlateDetection: false
                    )
                }
            }
            
            var results: [MultiCamSyncResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        
        // All operations should complete successfully
        XCTAssertEqual(results.count, 10)
        for result in results {
            XCTAssertNotNil(result)
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateSilentAudio(duration: Double) throws -> URL {
        let url = testAudioDirectory.appendingPathComponent("silent_\(Date().timeIntervalSince1970).wav")
        let sampleRate: Double = 48000
        let totalSamples = Int(duration * sampleRate)
        let audioData = [Float](repeating: 0, count: totalSamples)
        
        try writeWAVFile(audioData: audioData, sampleRate: sampleRate, url: url)
        return url
    }
    
    private func generateTestAudio(sampleRate: Double, duration: Double, offset: Double = 0) throws -> URL {
        let url = testAudioDirectory.appendingPathComponent("test_\(sampleRate)_\(Date().timeIntervalSince1970).wav")
        let samplesPerSecond = sampleRate
        let totalSamples = Int(duration * sampleRate)
        var audioData = [Float](repeating: 0, count: totalSamples)
        
        // Add a click every second
        let clickOffset = Int(offset * sampleRate)
        for second in 0..<Int(duration) {
            let sampleIndex = clickOffset + Int(Double(second) * samplesPerSecond)
            if sampleIndex < totalSamples {
                audioData[sampleIndex] = 1.0
            }
        }
        
        try writeWAVFile(audioData: audioData, sampleRate: sampleRate, url: url)
        return url
    }
    
    private func generateNoisyAudio(duration: Double, noiseLevel: Float) throws -> URL {
        let url = testAudioDirectory.appendingPathComponent("noisy_\(Date().timeIntervalSince1970).wav")
        let sampleRate: Double = 48000
        let totalSamples = Int(duration * sampleRate)
        var audioData = [Float](repeating: 0, count: totalSamples)
        
        // Generate white noise
        for i in 0..<totalSamples {
            audioData[i] = Float.random(in: -noiseLevel...noiseLevel)
        }
        
        try writeWAVFile(audioData: audioData, sampleRate: sampleRate, url: url)
        return url
    }
    
    private func generateAudioWithGaps(duration: Double, gapDuration: Double) throws -> URL {
        let url = testAudioDirectory.appendingPathComponent("gapped_\(Date().timeIntervalSince1970).wav")
        let sampleRate: Double = 48000
        let totalSamples = Int(duration * sampleRate)
        var audioData = [Float](repeating: 0, count: totalSamples)
        
        // Add signal with gaps
        let gapSamples = Int(gapDuration * sampleRate)
        let signalLength = (totalSamples - gapSamples) / 2
        
        // First signal segment
        for i in 0..<signalLength {
            audioData[i] = sin(2 * Float.pi * 440 * Float(i) / Float(sampleRate)) * 0.5
        }
        
        // Gap (already silent)
        
        // Second signal segment
        let secondStart = signalLength + gapSamples
        for i in 0..<signalLength {
            if secondStart + i < totalSamples {
                audioData[secondStart + i] = sin(2 * Float.pi * 440 * Float(i) / Float(sampleRate)) * 0.5
            }
        }
        
        try writeWAVFile(audioData: audioData, sampleRate: sampleRate, url: url)
        return url
    }
    
    private func writeWAVFile(audioData: [Float], sampleRate: Double, url: URL) throws {
        let sampleRate = UInt32(sampleRate)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 32
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        
        var header = [UInt8]()
        
        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(36 + UInt32(audioData.count * 4)).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        
        // fmt chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // IEEE float
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(audioData.count * 4).littleEndian) { Array($0) })
        
        let data = NSMutableData()
        data.append(header, length: header.count)
        
        for sample in audioData {
            var floatSample = sample.littleEndian
            data.append(&floatSample, length: MemoryLayout<Float>.size)
        }
        
        try data.write(to: url)
    }
}
