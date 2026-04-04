import Foundation
import SLATESharedTypes

public struct ClipAnalysisResult: Sendable {
    public let aiScores: AIScores
    public let transcript: Transcript?

    public init(aiScores: AIScores, transcript: Transcript?) {
        self.aiScores = aiScores
        self.transcript = transcript
    }
}

public struct AIPipeline: Sendable {
    private let visionScorer: VisionScorer
    private let audioScorer: AudioScorer
    private let transcriptionService: TranscriptionService
    private let performanceScorer: PerformanceScorer
    private let baseModelVersion = "hybrid-local-v3"
    private var confidenceTracker = ConfidenceTracker()

    public init(
        visionScorer: VisionScorer = .init(),
        audioScorer: AudioScorer = .init(),
        transcriptionService: TranscriptionService = .init(),
        performanceScorer: PerformanceScorer = .init()
    ) {
        self.visionScorer = visionScorer
        self.audioScorer = audioScorer
        self.transcriptionService = transcriptionService
        self.performanceScorer = performanceScorer
    }

    public func scoreClip(_ clip: Clip) async throws -> AIScores {
        try await analyzeClip(clip).aiScores
    }

    public func analyzeClip(_ clip: Clip) async throws -> ClipAnalysisResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        var focus = 0.0
        var exposure = 0.0
        var stability = 0.0
        var audio = 0.0
        var reasons: [ScoreReason] = []
        var visionModelType = ConfidenceTracker.ModelType.visionHeuristic

        if let proxyPath = clip.proxyPath {
            let proxyURL = URL(fileURLWithPath: proxyPath)
            if FileManager.default.fileExists(atPath: proxyURL.path) {
                let visionStart = CFAbsoluteTimeGetCurrent()
                let vision = try await visionScorer.scoreClip(proxyURL: proxyURL, fps: clip.sourceFps)
                let visionTime = CFAbsoluteTimeGetCurrent() - visionStart
                
                focus = vision.focus
                exposure = vision.exposure
                stability = vision.stability
                reasons.append(contentsOf: vision.reasons)
                
                // Determine model type from result
                if vision.modelVersion.contains("coreml") {
                    visionModelType = .visionCoreML
                } else if vision.modelVersion.contains("optimized") {
                    visionModelType = .visionOptimized
                }
                
                // Track confidence
                let inputSize = ConfidenceTracker.InputSize(
                    duration: clip.duration,
                    frameCount: Int(clip.duration * clip.sourceFps),
                    resolution: CGSize(width: 1920, height: 1080) // Would extract from actual video
                )
                
                confidenceTracker.recordVisionInference(
                    modelVersion: vision.modelVersion,
                    modelType: visionModelType,
                    confidence: vision.confidence,
                    processingTime: visionTime,
                    inputSize: inputSize,
                    additionalMetrics: [
                        "focus": vision.focus,
                        "exposure": vision.exposure,
                        "stability": vision.stability
                    ]
                )
            } else {
                reasons.append(
                    .init(
                        dimension: "vision",
                        score: 0,
                        flag: .warning,
                        message: "Proxy path does not exist yet; returning advisory vision scores."
                    )
                )
            }
        } else {
            reasons.append(
                .init(
                    dimension: "vision",
                    score: 0,
                    flag: .warning,
                    message: "Proxy is missing, so vision scoring could not run."
                )
            )
        }

        var transcript: Transcript?
        if let audioURL = resolvedAudioURL(for: clip) {
            let audioStart = CFAbsoluteTimeGetCurrent()
            let scoredAudio = try await audioScorer.scoreAudio(syncedAudioURL: audioURL)
            let audioTime = CFAbsoluteTimeGetCurrent() - audioStart
            
            audio = scoredAudio.audio
            reasons.append(contentsOf: scoredAudio.reasons)
            
            // Track audio confidence
            let audioInputSize = ConfidenceTracker.InputSize(
                duration: clip.duration,
                sampleCount: Int(clip.duration * 48000) // Assuming 48kHz
            )
            
            confidenceTracker.recordAudioInference(
                modelVersion: "audio-heuristic-v1",
                modelType: .audioHeuristic,
                confidence: Double(scoredAudio.audio) / 100.0,
                processingTime: audioTime,
                inputSize: audioInputSize,
                additionalMetrics: ["audioScore": scoredAudio.audio]
            )
            
            let transcriptStart = CFAbsoluteTimeGetCurrent()
            transcript = try await transcriptionService.transcribe(audioURL: audioURL)
            let transcriptTime = CFAbsoluteTimeGetCurrent() - transcriptStart
            
            // Track transcription confidence
            if let confidence = transcript?.averageConfidence {
                confidenceTracker.recordTranscriptionInference(
                    modelVersion: "whisper-v1",
                    confidence: confidence,
                    processingTime: transcriptTime,
                    inputSize: audioInputSize
                )
            }
        } else {
            reasons.append(
                .init(
                    dimension: "audio",
                    score: 0,
                    flag: .warning,
                    message: "No external or embedded audio source was available, so audio scoring could not run."
                )
            )
        }

        let totalProcessingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        let weightedVision = (focus * 0.35) + (exposure * 0.35) + (stability * 0.30)
        let composite = max(0, min(100, (weightedVision * 0.70) + (audio * 0.30)))

        let performance: Double?
        let contentDensity: Double?
        let performanceModelVersion: String?

        switch clip.projectMode {
        case .narrative:
            let performanceResult = try await performanceScorer.scorePerformance(
                transcript: transcript ?? Transcript(text: "", language: nil, words: []),
                scriptText: "",
                clipMode: clip.projectMode
            )
            performance = performanceResult.score
            contentDensity = nil
            performanceModelVersion = performanceResult.modelVersion
            reasons.append(contentsOf: performanceResult.reasons)
        case .documentary:
            performance = nil
            let densityResult = documentaryContentDensity(transcript: transcript ?? Transcript(text: "", language: nil, words: []))
            contentDensity = densityResult.score
            performanceModelVersion = nil
            reasons.append(contentsOf: densityResult.reasons)
        }

        let scores = AIScores(
            composite: composite,
            focus: focus,
            exposure: exposure,
            stability: stability,
            audio: audio,
            performance: performance,
            contentDensity: contentDensity,
            scoredAt: ISO8601DateFormatter().string(from: Date()),
            modelVersion: composedModelVersion(performanceModelVersion: performanceModelVersion),
            reasoning: reasons
        )

        return ClipAnalysisResult(aiScores: scores, transcript: transcript)
    }

    private func documentaryContentDensity(transcript: Transcript) -> (score: Double?, reasons: [ScoreReason]) {
        let words = transcript.words.sorted { $0.start < $1.start }
        guard let first = words.first, let last = words.last else {
            return (
                nil,
                [
                    .init(
                        dimension: "contentDensity",
                        score: 0,
                        flag: .warning,
                        message: "Documentary content density could not be derived because the transcript was empty."
                    )
                ]
            )
        }

        let totalDuration = max(last.end - first.start, 0.01)
        let wordsPerMinute = (Double(words.count) / totalDuration) * 60
        let speechCoverage = words.reduce(0.0) { partial, word in
            partial + max(word.end - word.start, 0)
        } / totalDuration

        let densityScore = max(
            0,
            min(
                100,
                (max(0, min(100, 100 - abs(wordsPerMinute - 155) * 0.55)) * 0.60) +
                (max(0, min(100, 100 - abs(speechCoverage - 0.70) * 140)) * 0.40)
            )
        )

        let reason: ScoreReason
        if speechCoverage < 0.25 {
            reason = .init(
                dimension: "contentDensity",
                score: densityScore,
                flag: .warning,
                message: "Interview coverage is sparse; the clip spends long stretches without spoken content."
            )
        } else if wordsPerMinute > 220 {
            reason = .init(
                dimension: "contentDensity",
                score: densityScore,
                flag: .warning,
                message: "Speech density is very high, which may make the clip harder to skim during review."
            )
        } else {
            reason = .init(
                dimension: "contentDensity",
                score: densityScore,
                flag: .info,
                message: "Transcript-derived density score reflects how much spoken material the clip packs into its runtime."
            )
        }

        return (densityScore, [reason])
    }

    private func resolvedAudioURL(for clip: Clip) -> URL? {
        let candidates = [clip.syncedAudioPath, clip.sourcePath, clip.proxyPath]
            .compactMap { $0 }
            .map { URL(fileURLWithPath: $0) }

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func composedModelVersion(performanceModelVersion: String?) -> String {
        guard let performanceModelVersion, !performanceModelVersion.isEmpty else {
            return baseModelVersion
        }
        return "\(baseModelVersion)+\(performanceModelVersion)"
    }
}

public typealias SLATEAIPipeline = AIPipeline
