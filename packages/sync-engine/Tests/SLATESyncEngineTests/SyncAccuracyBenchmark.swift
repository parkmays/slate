import Foundation
import XCTest
import SLATESyncEngine

/// Benchmark harness for testing sync accuracy across various scenarios
class SyncAccuracyBenchmark: XCTestCase {
    
    private let testResults = SyncBenchmarkResults()
    private let testDataDirectory = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources")
        .appendingPathComponent("BenchmarkData")
    
    override func setUp() async throws {
        try await super.setUp()
        // Create test data directory if it doesn't exist
        try FileManager.default.createDirectory(at: testDataDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Benchmark Test Cases
    
    func testSyncAccuracyBenchmark() async throws {
        let syncEngine = SyncEngine()
        
        // Test scenarios with known offsets
        let scenarios = [
            SyncScenario(
                name: "Perfect Sync",
                primaryOffset: 0.0,
                secondaryOffset: 0.0,
                expectedOffset: 0,
                fps: 24,
                description: "No offset between cameras"
            ),
            SyncScenario(
                name: "1 Frame Offset",
                primaryOffset: 0.0,
                secondaryOffset: 1.0/24,
                expectedOffset: 1,
                fps: 24,
                description: "Single frame offset"
            ),
            SyncScenario(
                name: "5 Frame Offset",
                primaryOffset: 0.0,
                secondaryOffset: 5.0/24,
                expectedOffset: 5,
                fps: 24,
                description: "Multiple frame offset"
            ),
            SyncScenario(
                name: "Drift Scenario",
                primaryOffset: 0.0,
                secondaryOffset: 0.0,
                expectedOffset: 0,
                fps: 23.976,
                description: "Slight frame rate difference causing drift"
            ),
            SyncScenario(
                name: "Noise Scenario",
                primaryOffset: 0.0,
                secondaryOffset: 2.0/24,
                expectedOffset: 2,
                fps: 30,
                description: "Offset with background noise",
                noiseLevel: 0.1
            )
        ]
        
        for scenario in scenarios {
            let result = try await runSyncScenario(scenario, syncEngine: syncEngine)
            testResults.addResult(result)
            
            // Log scenario results
            print("\n=== \(scenario.name) ===")
            print("Description: \(scenario.description)")
            print("Expected offset: \(scenario.expectedOffset) frames")
            print("Detected offset: \(result.detectedOffset) frames")
            print("Error: \(result.errorFrames) frames")
            print("Confidence: \(result.confidence)")
            print("Processing time: \(String(format: "%.3f", result.processingTime))s")
            
            // Assert accuracy requirements
            XCTAssertLessThanOrEqual(abs(result.errorFrames), 1, "Sync accuracy should be within 1 frame for \(scenario.name)")
            XCTAssertGreaterThanOrEqual(result.confidence.rawValue, 2, "Confidence should be at least medium for \(scenario.name)")
        }
        
        // Generate benchmark report
        let report = testResults.generateReport()
        print("\n=== BENCHMARK REPORT ===")
        print(report)
        
        // Save report to file
        let reportURL = testDataDirectory.appendingPathComponent("SyncBenchmarkReport_\(Date().timeIntervalSince1970).json")
        try report.save(to: reportURL)
        
        // Overall assertions
        let averageError = testResults.averageErrorFrames
        XCTAssertLessThanOrEqual(averageError, 0.5, "Average sync error should be less than 0.5 frames")
        
        let averageProcessingTime = testResults.averageProcessingTime
        XCTAssertLessThanOrEqual(averageProcessingTime, 30.0, "Average processing time should be under 30 seconds")
    }
    
    // MARK: - Private Methods
    
    private func runSyncScenario(_ scenario: SyncScenario, syncEngine: SyncEngine) async throws -> SyncBenchmarkResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Generate test audio files with specified offsets
        let primaryURL = try generateTestAudio(
            offset: scenario.primaryOffset,
            fps: scenario.fps,
            duration: 60, // 1 minute
            noiseLevel: 0.0,
            filename: "primary_\(scenario.name.replacingOccurrences(of: " ", with: "_")).wav"
        )
        
        let secondaryURL = try generateTestAudio(
            offset: scenario.secondaryOffset,
            fps: scenario.fps,
            duration: 60,
            noiseLevel: scenario.noiseLevel ?? 0.0,
            filename: "secondary_\(scenario.name.replacingOccurrences(of: " ", with: "_")).wav"
        )
        
        // Run sync detection
        let result = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: scenario.fps,
            useSlateDetection: false
        )
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        // Calculate error
        let errorFrames = abs(result.offsetFrames - scenario.expectedOffset)
        
        return SyncBenchmarkResult(
            scenario: scenario,
            detectedOffset: result.offsetFrames,
            expectedOffset: scenario.expectedOffset,
            errorFrames: errorFrames,
            confidence: result.confidence,
            processingTime: processingTime,
            method: result.method
        )
    }
    
    private func generateTestAudio(
        offset: Double,
        fps: Double,
        duration: Double,
        noiseLevel: Float,
        filename: String
    ) throws -> URL {
        let url = testDataDirectory.appendingPathComponent(filename)
        
        // Generate a test tone with claps at each frame boundary
        let sampleRate: Double = 48000
        let samplesPerFrame = sampleRate / fps
        let totalSamples = Int(duration * sampleRate)
        
        // Create audio buffer
        var audioData = [Float](repeating: 0, count: totalSamples)
        
        // Add claps at frame boundaries with offset
        let clapOffset = Int(offset * sampleRate)
        for frame in 0..<Int(duration * fps) {
            let sampleIndex = clapOffset + Int(Double(frame) * samplesPerFrame)
            if sampleIndex < totalSamples {
                // Generate a clap (short burst of white noise)
                let clapLength = Int(0.001 * sampleRate) // 1ms clap
                for i in 0..<clapLength {
                    if sampleIndex + i < totalSamples {
                        // White noise with envelope
                        let envelope = exp(-Float(i) / Float(clapLength) * 5)
                        audioData[sampleIndex + i] = (Float.random(in: -1...1) * envelope + Float.random(in: -noiseLevel...noiseLevel))
                    }
                }
            }
        }
        
        // Add ambient noise throughout
        if noiseLevel > 0 {
            for i in 0..<totalSamples {
                audioData[i] += Float.random(in: -noiseLevel...noiseLevel)
            }
        }
        
        // Write to WAV file
        try writeWAVFile(audioData: audioData, sampleRate: sampleRate, url: url)
        
        return url
    }
    
    private func writeWAVFile(audioData: [Float], sampleRate: Double, url: URL) throws {
        // WAV file header
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
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // IEEE float
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(audioData.count * 4).littleEndian) { Array($0) })
        
        // Write file
        let data = NSMutableData()
        data.append(header, length: header.count)
        
        // Convert float samples to little-endian bytes
        for sample in audioData {
            var floatSample = sample.littleEndian
            data.append(&floatSample, length: MemoryLayout<Float>.size)
        }
        
        try data.write(to: url)
    }
}

// MARK: - Supporting Types

struct SyncScenario {
    let name: String
    let primaryOffset: Double
    let secondaryOffset: Double
    let expectedOffset: Int
    let fps: Double
    let description: String
    let noiseLevel: Float?
}

struct SyncBenchmarkResult {
    let scenario: SyncScenario
    let detectedOffset: Int
    let expectedOffset: Int
    let errorFrames: Int
    let confidence: SyncConfidence
    let processingTime: TimeInterval
    let method: MultiCamSyncMethod
}

class SyncBenchmarkResults {
    private var results: [SyncBenchmarkResult] = []
    
    func addResult(_ result: SyncBenchmarkResult) {
        results.append(result)
    }
    
    var averageErrorFrames: Double {
        guard !results.isEmpty else { return 0 }
        return results.reduce(0) { $0 + Double($1.errorFrames) } / Double(results.count)
    }
    
    var averageProcessingTime: TimeInterval {
        guard !results.isEmpty else { return 0 }
        return results.reduce(0) { $0 + $1.processingTime } / Double(results.count)
    }
    
    var maxErrorFrames: Int {
        return results.map(\.errorFrames).max() ?? 0
    }
    
    var successRate: Double {
        guard !results.isEmpty else { return 0 }
        let successful = results.filter { $0.errorFrames <= 1 }.count
        return Double(successful) / Double(results.count)
    }
    
    func generateReport() -> String {
        var report = ""
        report += "Sync Accuracy Benchmark Results\n"
        report += "================================\n\n"
        report += "Total scenarios: \(results.count)\n"
        report += "Average error: \(String(format: "%.2f", averageErrorFrames)) frames\n"
        report += "Max error: \(maxErrorFrames) frames\n"
        report += "Success rate (≤1 frame): \(String(format: "%.1f", successRate * 100))%\n"
        report += "Average processing time: \(String(format: "%.3f", averageProcessingTime))s\n\n"
        
        report += "Detailed Results:\n"
        report += "---------------\n"
        
        for result in results {
            report += "\n\(result.scenario.name):\n"
            report += "  Expected: \(result.expectedOffset) frames\n"
            report += "  Detected: \(result.detectedOffset) frames\n"
            report += "  Error: \(result.errorFrames) frames\n"
            report += "  Confidence: \(result.confidence)\n"
            report += "  Method: \(result.method)\n"
            report += "  Time: \(String(format: "%.3f", result.processingTime))s\n"
        }
        
        return report
    }
}

extension SyncBenchmarkResults {
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let data = try encoder.encode(results)
        try data.write(to: url)
    }
}
