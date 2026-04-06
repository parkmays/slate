import AVFoundation
import Foundation
import SLATESharedTypes

/// Consistent API wrapper for SyncEngine operations
public struct SyncEngineAPI {

    public enum SyncError: Error, LocalizedError {
        case invalidInput(String)
        case processingFailed(Error)
        case timeout
        case insufficientData

        public var errorDescription: String? {
            switch self {
            case .invalidInput(let message):
                return "Invalid input: \(message)"
            case .processingFailed(let error):
                return "Processing failed: \(error.localizedDescription)"
            case .timeout:
                return "Operation timed out"
            case .insufficientData:
                return "Insufficient data for processing"
            }
        }
    }

    private let engine: SyncEngine
    private let logger: SLATELogger
    private let configuration: SLATEConfiguration.SyncEngine

    public init(
        engine: SyncEngine = SyncEngine(),
        configuration: SLATEConfiguration.SyncEngine = .init()
    ) {
        self.engine = engine
        self.configuration = configuration
        self.logger = SLATELogger(category: "SyncEngineAPI")
    }

    // MARK: - Consistent Sync Methods

    /// Synchronize two audio clips with consistent error handling
    public func syncClips(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> MultiCamSyncResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        logger.info("Starting sync operation", metadata: [
            "primary": primary.lastPathComponent,
            "secondary": secondary.lastPathComponent,
            "fps": fps
        ])

        do {
            try await validateInputs(primary: primary, secondary: secondary, fps: fps)

            let primarySize = try FileManager.default.attributesOfItem(atPath: primary.path)[.size] as? Int ?? 0
            let secondarySize = try FileManager.default.attributesOfItem(atPath: secondary.path)[.size] as? Int ?? 0

            let result: MultiCamSyncResult
            if configuration.shouldUseStreaming(fileSize: max(primarySize, secondarySize)) {
                logger.info("Using streaming processing for large files")
                result = try await syncWithStreaming(primary: primary, secondary: secondary, fps: fps)
            } else {
                result = try await engine.syncMultiCam(
                    primaryCamera: primary,
                    additionalCameras: [secondary],
                    fps: fps
                )
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let first = result.offsets.first

            logger.info("Sync completed successfully", metadata: [
                "offsetFrames": first?.offsetFrames ?? 0,
                "confidence": first?.confidence.rawValue ?? result.overallConfidence.rawValue,
                "method": first?.method.rawValue ?? result.overallConfidence.rawValue,
                "duration": duration
            ])

            await MetricsManager.shared.recordPerformance(
                operation: "sync",
                duration: duration,
                metadata: [
                    "method": first?.method.rawValue ?? "unknown",
                    "confidence": first?.confidence.rawValue ?? result.overallConfidence.rawValue,
                    "fileSize": max(primarySize, secondarySize)
                ]
            )

            return result

        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime

            logger.error("Sync failed", metadata: [
                "duration": duration,
                "error": error.localizedDescription
            ], error: error)

            throw SyncError.processingFailed(error)
        }
    }

    /// Assign audio roles with consistent error handling
    public func assignAudioRoles(tracks: [URL]) async throws -> [AudioTrack] {
        logger.info("Assigning audio roles", metadata: [
            "trackCount": tracks.count
        ])

        guard !tracks.isEmpty else {
            throw SyncError.invalidInput("No audio tracks provided")
        }

        for track in tracks {
            guard FileManager.default.fileExists(atPath: track.path) else {
                throw SyncError.invalidInput("Audio file not found: \(track.lastPathComponent)")
            }
        }

        let result = await engine.assignAudioRoles(tracks: tracks)

        logger.info("Audio roles assigned", metadata: [
            "assignedRoles": result.map { $0.role.rawValue }
        ])

        return result
    }

    /// Get performance metrics with consistent format
    public func getPerformanceMetrics() -> SyncPerformanceMetrics? {
        nil
    }

    // MARK: - Private Methods

    private func validateInputs(primary: URL, secondary: URL, fps: Double) async throws {
        guard FileManager.default.fileExists(atPath: primary.path) else {
            throw SyncError.invalidInput("Primary audio file not found")
        }

        guard FileManager.default.fileExists(atPath: secondary.path) else {
            throw SyncError.invalidInput("Secondary audio file not found")
        }

        guard fps > 0 && fps <= 120 else {
            throw SyncError.invalidInput("Invalid FPS value: \(fps)")
        }

        let primaryDuration = try await getAudioDuration(primary)
        let secondaryDuration = try await getAudioDuration(secondary)

        let minDuration = configuration.audio.minDurationSeconds
        guard primaryDuration >= minDuration && secondaryDuration >= minDuration else {
            throw SyncError.insufficientData
        }
    }

    private func getAudioDuration(_ url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw SyncError.invalidInput("Could not read duration for \(url.lastPathComponent)")
        }
        return seconds
    }

    private func syncWithStreaming(
        primary: URL,
        secondary: URL,
        fps: Double
    ) async throws -> MultiCamSyncResult {
        let processor = StreamingAudioProcessor(
            maxMemoryUsage: configuration.performance.streamingMemoryLimit
        )

        logger.info("Performing streaming correlation")

        let correlation = try await processor.correlateStreaming(
            primaryURL: primary,
            secondaryURL: secondary,
            maxLag: Int(30 * fps)
        )

        let confidence = determineConfidence(score: correlation.score)

        return MultiCamSyncResult(
            primaryCamera: primary,
            offsets: [
                CameraOffset(
                    cameraURL: secondary,
                    offsetFrames: correlation.lag,
                    offsetSeconds: Double(correlation.lag) / fps,
                    confidence: confidence,
                    method: .audioCorrelation
                )
            ],
            overallConfidence: confidence,
            notes: ["streaming correlation"]
        )
    }

    private func determineConfidence(score: Float) -> SyncConfidence {
        switch score {
        case 0.9...1.0:
            return .high
        case 0.7..<0.9:
            return .medium
        case 0.5..<0.7:
            return .low
        default:
            return .manualRequired
        }
    }
}
