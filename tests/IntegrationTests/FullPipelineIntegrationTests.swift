import XCTest
import Foundation
import SLATESyncEngine
import SLATEAIPipeline
import SLATESharedTypes

/// Integration tests for the full AI/ML pipeline
@available(macOS 14.0, *)
final class FullPipelineIntegrationTests: XCTestCase {
    
    private var testDirectory: URL!
    private var syncEngine: SyncEngine!
    private var aiPipeline: AIPipeline!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test directory
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SLATEIntegrationTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        
        // Initialize components
        syncEngine = SyncEngine()
        aiPipeline = AIPipeline()
    }
    
    override func tearDown() async throws {
        // Clean up test directory
        try? FileManager.default.removeItem(at: testDirectory)
        try await super.tearDown()
    }
    
    // MARK: - Test Scenarios
    
    func testFullPipelineWithPerfectSync() async throws {
        // Create test media with perfect sync
        let (primaryURL, secondaryURL, proxyURL) = try createTestMedia(
            primaryOffset: 0,
            secondaryOffset: 0,
            duration: 30,
            fps: 24
        )
        
        // Step 1: Sync audio
        let syncResult = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 24
        )
        
        // Verify sync
        XCTAssertEqual(syncResult.offsetFrames, 0)
        XCTAssertGreaterThanOrEqual(syncResult.confidence.rawValue, 2) // medium or high
        
        // Step 2: Assign audio roles
        let audioTracks = await syncEngine.assignAudioRoles(tracks: [primaryURL, secondaryURL])
        XCTAssertEqual(audioTracks.count, 2)
        
        // Step 3: Create clip with sync data
        let clip = createTestClip(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            proxyURL: proxyURL,
            syncResult: syncResult,
            audioTracks: audioTracks
        )
        
        // Step 4: Run AI analysis
        let analysisResult = try await aiPipeline.analyzeClip(clip)
        
        // Verify AI scores
        XCTAssertNotNil(analysisResult.aiScores)
        XCTAssertGreaterThanOrEqual(analysisResult.aiScores.composite, 0)
        XCTAssertLessThanOrEqual(analysisResult.aiScores.composite, 100)
        
        // Step 5: Verify end-to-end result
        XCTAssertNotNil(analysisResult.transcript)
        XCTAssertEqual(clip.aiProcessingStatus, .ready)
    }
    
    func testPipelineWithFrameOffset() async throws {
        // Test with 2 frame offset
        let (primaryURL, secondaryURL, proxyURL) = try createTestMedia(
            primaryOffset: 0,
            secondaryOffset: 2.0 / 24,
            duration: 60,
            fps: 24
        )
        
        // Sync should detect the offset
        let syncResult = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 24
        )
        
        XCTAssertEqual(syncResult.offsetFrames, 2)
        XCTAssertGreaterThanOrEqual(syncResult.confidence.rawValue, 2)
        
        // AI pipeline should still work with synced audio
        let clip = createTestClip(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            proxyURL: proxyURL,
            syncResult: syncResult,
            audioTracks: await syncEngine.assignAudioRoles(tracks: [primaryURL, secondaryURL])
        )
        
        let analysisResult = try await aiPipeline.analyzeClip(clip)
        XCTAssertNotNil(analysisResult.aiScores)
    }
    
    func testPipelineWithNoisyAudio() async throws {
        // Create noisy audio
        let (primaryURL, secondaryURL, proxyURL) = try createTestMedia(
            primaryOffset: 0,
            secondaryOffset: 1.0 / 24,
            duration: 30,
            fps: 24,
            noiseLevel: 0.3
        )
        
        // Sync should still work but with lower confidence
        let syncResult = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 24
        )
        
        XCTAssertEqual(syncResult.offsetFrames, 1)
        XCTAssertEqual(syncResult.confidence, .low) // Expected with noise
        
        // Pipeline should gracefully degrade
        let clip = createTestClip(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            proxyURL: proxyURL,
            syncResult: syncResult,
            audioTracks: await syncEngine.assignAudioRoles(tracks: [primaryURL, secondaryURL])
        )
        
        let analysisResult = try await aiPipeline.analyzeClip(clip)
        XCTAssertNotNil(analysisResult.aiScores)
        // Scores might be lower with noisy audio
    }
    
    func testPipelinePerformanceTargets() async throws {
        // Test 10-minute video to verify performance targets
        let (primaryURL, secondaryURL, proxyURL) = try createTestMedia(
            primaryOffset: 0,
            secondaryOffset: 5.0 / 24,
            duration: 600, // 10 minutes
            fps: 24
        )
        
        // Measure sync performance
        let syncStart = CFAbsoluteTimeGetCurrent()
        let syncResult = try await syncEngine.syncClip(
            primary: primaryURL,
            secondary: secondaryURL,
            fps: 24
        )
        let syncTime = CFAbsoluteTimeGetCurrent() - syncStart
        
        // Verify sync meets 30-second target
        XCTAssertLessThanOrEqual(syncTime, 30.0, "Sync should complete in under 30 seconds")
        print("Sync time for 10-minute video: \(String(format: "%.2f", syncTime))s")
        
        // Measure AI pipeline performance
        let clip = createTestClip(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL,
            proxyURL: proxyURL,
            syncResult: syncResult,
            audioTracks: await syncEngine.assignAudioRoles(tracks: [primaryURL, secondaryURL])
        )
        
        let aiStart = CFAbsoluteTimeGetCurrent()
        let analysisResult = try await aiPipeline.analyzeClip(clip)
        let aiTime = CFAbsoluteTimeGetCurrent() - aiStart
        
        // Verify AI meets 60-second target (45s vision + 15s audio)
        XCTAssertLessThanOrEqual(aiTime, 60.0, "AI analysis should complete in under 60 seconds")
        print("AI analysis time for 10-minute video: \(String(format: "%.2f", aiTime))s")
        
        // Verify total pipeline time
        let totalTime = syncTime + aiTime
        XCTAssertLessThanOrEqual(totalTime, 90.0, "Full pipeline should complete in under 90 seconds")
        print("Total pipeline time: \(String(format: "%.2f", totalTime))s")
    }
    
    func testConcurrentPipelineProcessing() async throws {
        // Create multiple clips
        let clips = try (0..<4).map { i in
            let offset = Double(i) / 24
            let (primary, secondary, proxy) = try createTestMedia(
                primaryOffset: 0,
                secondaryOffset: offset,
                duration: 30,
                fps: 24
            )
            return (primary, secondary, proxy, offset)
        }
        
        // Process all clips concurrently
        let results = try await withThrowingTaskGroup(of: PipelineResult.self) { group in
            for (index, (primary, secondary, proxy, offset)) in clips.enumerated() {
                group.addTask {
                    return try await self.processClip(
                        id: index,
                        primaryURL: primary,
                        secondaryURL: secondary,
                        proxyURL: proxy,
                        expectedOffset: Int(offset * 24)
                    )
                }
            }
            
            var results: [PipelineResult] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.id < $1.id }
        }
        
        // Verify all clips processed successfully
        XCTAssertEqual(results.count, 4)
        for result in results {
            XCTAssertNotNil(result.syncResult)
            XCTAssertNotNil(result.aiScores)
            XCTAssertEqual(result.syncError, nil)
            XCTAssertEqual(result.aiError, nil)
        }
    }
    
    func testGracefulDegradation() async throws {
        // Create corrupted audio file
        let corruptedURL = testDirectory.appendingPathComponent("corrupted.wav")
        let corruptedData = Data([0x52, 0x49, 0x46, 0x46] + Array(repeating: 0, count: 1000))
        try corruptedData.write(to: corruptedURL)
        
        let (primaryURL, _, proxyURL) = try createTestMedia(
            primaryOffset: 0,
            secondaryOffset: 0,
            duration: 30,
            fps: 24
        )
        
        // Sync should handle corrupted file gracefully
        do {
            _ = try await syncEngine.syncClip(
                primary: primaryURL,
                secondary: corruptedURL,
                fps: 24
            )
            XCTFail("Should have thrown an error")
        } catch {
            // Expected - should fall back to manual_required
        }
        
        // AI pipeline should handle missing proxy gracefully
        let clip = Clip(
            id: UUID().uuidString,
            projectId: UUID().uuidString,
            checksum: "test",
            sourcePath: primaryURL.path,
            sourceSize: 1000000,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 30,
            proxyPath: nil, // Missing proxy
            proxyStatus: .error,
            proxyChecksum: nil,
            proxyLUT: nil,
            proxyColorSpace: nil,
            narrativeMeta: nil,
            documentaryMeta: nil,
            audioTracks: [],
            syncResult: nil,
            syncedAudioPath: nil,
            cameraGroupId: nil,
            cameraAngle: nil,
            aiScores: nil,
            transcriptId: nil,
            aiProcessingStatus: .pending,
            reviewStatus: .unreviewed,
            annotations: [],
            approvalStatus: .pending,
            approvedBy: nil,
            approvedAt: nil,
            ingestedAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            projectMode: .documentary,
            cameraMetadata: nil
        )
        
        let analysisResult = try await aiPipeline.analyzeClip(clip)
        XCTAssertNotNil(analysisResult.aiScores)
        // Should have advisory reasons for missing proxy
    }
    
    // MARK: - Helper Methods
    
    private func createTestMedia(
        primaryOffset: Double,
        secondaryOffset: Double,
        duration: Double,
        fps: Double,
        noiseLevel: Float = 0.0
    ) throws -> (primary: URL, secondary: URL, proxy: URL) {
        let primaryURL = testDirectory.appendingPathComponent("primary.wav")
        let secondaryURL = testDirectory.appendingPathComponent("secondary.wav")
        let proxyURL = testDirectory.appendingPathComponent("proxy.mp4")
        
        // Generate audio files
        try generateTestAudio(
            url: primaryURL,
            duration: duration,
            offset: primaryOffset,
            noiseLevel: noiseLevel
        )
        
        try generateTestAudio(
            url: secondaryURL,
            duration: duration,
            offset: secondaryOffset,
            noiseLevel: noiseLevel
        )
        
        // Create a simple proxy video file (just empty file for testing)
        try Data().write(to: proxyURL)
        
        return (primaryURL, secondaryURL, proxyURL)
    }
    
    private func generateTestAudio(
        url: URL,
        duration: Double,
        offset: Double,
        noiseLevel: Float
    ) throws {
        let sampleRate: Double = 48000
        let samplesPerSecond = sampleRate
        let totalSamples = Int(duration * sampleRate)
        var audioData = [Float](repeating: 0, count: totalSamples)
        
        // Add click track for sync
        let clickInterval = samplesPerSecond / 2 // Click every 0.5 seconds
        let clickOffset = Int(offset * sampleRate)
        
        for i in stride(from: clickOffset, to: totalSamples, by: Int(clickInterval)) {
            guard i < totalSamples else { break }
            // Create a click
            let clickLength = Int(0.001 * sampleRate) // 1ms click
            for j in 0..<min(clickLength, totalSamples - i) {
                audioData[i + j] = Float.random(in: -1...1) * 0.5
            }
        }
        
        // Add noise
        if noiseLevel > 0 {
            for i in 0..<totalSamples {
                audioData[i] += Float.random(in: -noiseLevel...noiseLevel)
            }
        }
        
        // Write WAV file
        try writeWAVFile(audioData: audioData, sampleRate: sampleRate, url: url)
    }
    
    private func writeWAVFile(audioData: [Float], sampleRate: Double, url: URL) throws {
        // Simplified WAV writer
        let header: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, // "RIFF"
            0x24, 0x08, 0x00, 0x00, // File size - 8
            0x57, 0x41, 0x56, 0x45, // "WAVE"
            0x66, 0x6D, 0x74, 0x20, // "fmt "
            0x10, 0x00, 0x00, 0x00, // Chunk size
            0x03, 0x00,             // IEEE float
            0x01, 0x00,             // Mono
            0x40, 0x1F, 0x00, 0x00, // Sample rate (48000)
            0x80, 0x3E, 0x00, 0x00, // Byte rate
            0x04, 0x00,             // Block align
            0x20, 0x00,             // Bit depth
            0x64, 0x61, 0x74, 0x61, // "data"
            0x00, 0x08, 0x00, 0x00  // Data size
        ]
        
        let data = NSMutableData()
        data.append(header, length: header.count)
        
        for sample in audioData {
            var floatSample = sample.littleEndian
            data.append(&floatSample, length: MemoryLayout<Float>.size)
        }
        
        try data.write(to: url)
    }
    
    private func createTestClip(
        primaryURL: URL,
        secondaryURL: URL,
        proxyURL: URL,
        syncResult: MultiCamSyncResult,
        audioTracks: [AudioTrack]
    ) -> Clip {
        return Clip(
            id: UUID().uuidString,
            projectId: UUID().uuidString,
            checksum: "test",
            sourcePath: primaryURL.path,
            sourceSize: 1000000,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 30,
            proxyPath: proxyURL.path,
            proxyStatus: .ready,
            proxyChecksum: nil,
            proxyLUT: nil,
            proxyColorSpace: nil,
            narrativeMeta: nil,
            documentaryMeta: nil,
            audioTracks: audioTracks,
            syncResult: SyncResult(
                confidence: syncResult.confidence,
                method: syncResult.method,
                offsetFrames: syncResult.offsetFrames
            ),
            syncedAudioPath: secondaryURL.path,
            cameraGroupId: nil,
            cameraAngle: nil,
            aiScores: nil,
            transcriptId: nil,
            aiProcessingStatus: .pending,
            reviewStatus: .unreviewed,
            annotations: [],
            approvalStatus: .pending,
            approvedBy: nil,
            approvedAt: nil,
            ingestedAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            projectMode: .documentary,
            cameraMetadata: nil
        )
    }
    
    private func processClip(
        id: Int,
        primaryURL: URL,
        secondaryURL: URL,
        proxyURL: URL,
        expectedOffset: Int
    ) async throws -> PipelineResult {
        var syncResult: MultiCamSyncResult?
        var syncError: Error?
        var aiScores: AIScores?
        var aiError: Error?
        
        // Sync
        do {
            syncResult = try await syncEngine.syncClip(
                primary: primaryURL,
                secondary: secondaryURL,
                fps: 24
            )
        } catch {
            syncError = error
        }
        
        // AI Analysis
        if let syncResult = syncResult {
            let clip = createTestClip(
                primaryURL: primaryURL,
                secondaryURL: secondaryURL,
                proxyURL: proxyURL,
                syncResult: syncResult,
                audioTracks: await syncEngine.assignAudioRoles(tracks: [primaryURL, secondaryURL])
            )
            
            do {
                aiScores = try await aiPipeline.scoreClip(clip)
            } catch {
                aiError = error
            }
        }
        
        return PipelineResult(
            id: id,
            syncResult: syncResult,
            syncError: syncError,
            aiScores: aiScores,
            aiError: aiError
        )
    }
    
    private struct PipelineResult {
        let id: Int
        let syncResult: MultiCamSyncResult?
        let syncError: Error?
        let aiScores: AIScores?
        let aiError: Error?
    }
}
