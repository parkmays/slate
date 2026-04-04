import Foundation
import SLATESharedTypes

public struct PerformanceScoreResult: Codable, Sendable {
    public let score: Double?
    public let modelVersion: String
    public let reasons: [ScoreReason]

    public init(score: Double?, modelVersion: String, reasons: [ScoreReason]) {
        self.score = score
        self.modelVersion = modelVersion
        self.reasons = reasons
    }
}

typealias PerformanceInsightGenerator = @Sendable (GemmaPerformanceInsightRequest) async throws -> GemmaPerformanceInsightResponse?

public struct PerformanceScorer: Sendable {
    private let insightGenerator: PerformanceInsightGenerator

    public init() {
        self.insightGenerator = { (request: GemmaPerformanceInsightRequest) in
            try await GemmaService.shared.performanceInsight(for: request)
        }
    }

    init(
        insightGenerator: @escaping PerformanceInsightGenerator
    ) {
        self.insightGenerator = insightGenerator
    }

    public func scorePerformance(
        transcript: Transcript,
        scriptText: String,
        clipMode: ProjectMode
    ) async throws -> PerformanceScoreResult {
        guard clipMode == .narrative else {
            return PerformanceScoreResult(
                score: nil,
                modelVersion: "performance-heuristic-v1",
                reasons: [
                    .init(
                        dimension: "performance",
                        score: 0,
                        flag: .info,
                        message: "Performance scoring is only applied to narrative clips."
                    )
                ]
            )
        }

        let metrics = Self.metrics(from: transcript)
        guard metrics.totalDuration > 0 else {
            return PerformanceScoreResult(
                score: nil,
                modelVersion: "performance-heuristic-v1",
                reasons: [
                    .init(
                        dimension: "performance",
                        score: 0,
                        flag: .warning,
                        message: "No transcript timing data was available, so performance scoring could not run."
                    )
                ]
            )
        }

        _ = scriptText

        let speechCoverageScore = Self.bandScore(value: metrics.speechCoverage, ideal: 0.62, tolerance: 0.30)
        let phraseDurationScore = Self.bandScore(value: metrics.averagePhraseDuration, ideal: 1.9, tolerance: 1.2)
        let pauseCadenceScore = Self.bandScore(value: metrics.averagePauseDuration, ideal: 0.45, tolerance: 0.30)
        let pacingConsistencyScore = max(0, min(100, 100 - (metrics.phraseDurationVariance * 42)))
        let articulationScore = max(0, min(100, 100 - abs(metrics.wordsPerSecond - 2.8) * 18))

        let score = max(
            0,
            min(
                100,
                (speechCoverageScore * 0.28) +
                (phraseDurationScore * 0.22) +
                (pauseCadenceScore * 0.18) +
                (pacingConsistencyScore * 0.20) +
                (articulationScore * 0.12)
            )
        )

        var finalScore = score
        var reasons = Self.heuristicReasons(
            score: score,
            metrics: metrics,
            speechCoverageScore: speechCoverageScore,
            pauseCadenceScore: pauseCadenceScore,
            pacingConsistencyScore: pacingConsistencyScore
        )
        var modelVersion = "performance-heuristic-v1"

        let request = GemmaPerformanceInsightRequest(
            transcriptText: Self.truncated(transcript.text, limit: 12_000),
            transcriptLanguage: transcript.language,
            scriptText: Self.truncated(scriptText, limit: 4_000),
            heuristicScore: score,
            wordCount: transcript.words.count,
            metrics: .init(
                totalDuration: metrics.totalDuration,
                speechCoverage: metrics.speechCoverage,
                averagePhraseDuration: metrics.averagePhraseDuration,
                averagePauseDuration: metrics.averagePauseDuration,
                phraseDurationVariance: metrics.phraseDurationVariance,
                wordsPerSecond: metrics.wordsPerSecond
            )
        )

        do {
            if let insight = try await insightGenerator(request) {
                if let modelScore = insight.score {
                    finalScore = Self.blendedScore(heuristicScore: score, modelScore: modelScore)
                }

                let normalizedReasons = Self.normalizedGemmaReasons(
                    insight.reasons,
                    fallbackScore: finalScore
                )
                if normalizedReasons.isEmpty {
                    reasons.append(
                        .init(
                            dimension: "performance",
                            score: finalScore,
                            flag: .info,
                            message: "Gemma reviewed the take and found no additional narrative performance flags beyond the local pacing metrics."
                        )
                    )
                } else {
                    reasons.append(contentsOf: normalizedReasons)
                }
                modelVersion = "performance-hybrid-v2+\(insight.modelVersion)"
            }
        } catch {
            reasons.append(
                .init(
                    dimension: "performance",
                    score: finalScore,
                    flag: .warning,
                    message: "Gemma performance insight was unavailable (\(Self.shortErrorDescription(error))), so the score fell back to local pacing heuristics."
                )
            )
        }

        return PerformanceScoreResult(
            score: finalScore,
            modelVersion: modelVersion,
            reasons: reasons
        )
    }

    private struct TranscriptMetrics {
        let totalDuration: Double
        let speechCoverage: Double
        let averagePhraseDuration: Double
        let averagePauseDuration: Double
        let phraseDurationVariance: Double
        let wordsPerSecond: Double
    }

    private static func metrics(from transcript: Transcript) -> TranscriptMetrics {
        let orderedWords = transcript.words.sorted { $0.start < $1.start }
        guard let first = orderedWords.first, let last = orderedWords.last else {
            return TranscriptMetrics(
                totalDuration: 0,
                speechCoverage: 0,
                averagePhraseDuration: 0,
                averagePauseDuration: 0,
                phraseDurationVariance: 0,
                wordsPerSecond: 0
            )
        }

        let totalDuration = max(last.end - first.start, 0.01)
        let phrases = buildPhrases(from: orderedWords)
        let phraseDurations = phrases.map { max($0.end - $0.start, 0) }
        let pauses = zip(phrases.dropFirst(), phrases).map { max($0.0.start - $0.1.end, 0) }
        let speechCoverage = phraseDurations.reduce(0, +) / totalDuration
        let averagePhraseDuration = phraseDurations.isEmpty ? 0 : phraseDurations.reduce(0, +) / Double(phraseDurations.count)
        let averagePauseDuration = pauses.isEmpty ? 0.35 : pauses.reduce(0, +) / Double(pauses.count)
        let phraseVariance = variance(of: phraseDurations)
        let wordsPerSecond = Double(orderedWords.count) / totalDuration

        return TranscriptMetrics(
            totalDuration: totalDuration,
            speechCoverage: speechCoverage,
            averagePhraseDuration: averagePhraseDuration,
            averagePauseDuration: averagePauseDuration,
            phraseDurationVariance: phraseVariance,
            wordsPerSecond: wordsPerSecond
        )
    }

    private static func buildPhrases(from words: [TranscriptWord]) -> [(start: Double, end: Double)] {
        guard let first = words.first else { return [] }
        var phrases: [(start: Double, end: Double)] = [(first.start, first.end)]

        for word in words.dropFirst() {
            let gap = word.start - phrases[phrases.count - 1].end
            if gap > 0.55 {
                phrases.append((word.start, word.end))
            } else {
                phrases[phrases.count - 1].end = max(phrases[phrases.count - 1].end, word.end)
            }
        }

        return phrases
    }

    private static func variance(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
    }

    private static func bandScore(value: Double, ideal: Double, tolerance: Double) -> Double {
        guard tolerance > 0 else { return 0 }
        let normalizedDistance = abs(value - ideal) / tolerance
        return max(0, min(100, 100 - (normalizedDistance * 100)))
    }

    private static func heuristicReasons(
        score: Double,
        metrics: TranscriptMetrics,
        speechCoverageScore: Double,
        pauseCadenceScore: Double,
        pacingConsistencyScore: Double
    ) -> [ScoreReason] {
        var reasons: [ScoreReason] = []

        if metrics.speechCoverage < 0.25 {
            reasons.append(
                .init(
                    dimension: "performance",
                    score: speechCoverageScore,
                    flag: .warning,
                    message: "Long silent stretches dominated the take, which weakens performance coverage."
                )
            )
        }
        if metrics.averagePauseDuration > 0.9 {
            reasons.append(
                .init(
                    dimension: "performance",
                    score: pauseCadenceScore,
                    flag: .warning,
                    message: "Pauses between spoken phrases were unusually long and may indicate dropped pacing."
                )
            )
        }
        if metrics.phraseDurationVariance > 1.2 {
            reasons.append(
                .init(
                    dimension: "performance",
                    score: pacingConsistencyScore,
                    flag: .warning,
                    message: "Phrase timing varied sharply across the take, suggesting inconsistent delivery."
                )
            )
        }

        if reasons.isEmpty {
            reasons.append(
                .init(
                    dimension: "performance",
                    score: score,
                    flag: .info,
                    message: "Performance pacing stayed inside the preferred range for a narrative take."
                )
            )
        }

        return reasons
    }

    private static func normalizedGemmaReasons(
        _ reasons: [GemmaPerformanceInsightResponse.Reason],
        fallbackScore: Double
    ) -> [ScoreReason] {
        reasons.compactMap { reason in
            let message = reason.message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !message.isEmpty else {
                return nil
            }

            return ScoreReason(
                dimension: reason.dimension?.isEmpty == false ? reason.dimension! : "performance",
                score: max(0, min(100, reason.score ?? fallbackScore)),
                flag: ScoreFlag(rawValue: reason.flag.lowercased()) ?? .info,
                message: message,
                timecode: reason.timecode
            )
        }
    }

    private static func blendedScore(heuristicScore: Double, modelScore: Double) -> Double {
        max(0, min(100, (heuristicScore * 0.65) + (modelScore * 0.35)))
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    private static func shortErrorDescription(_ error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return "unknown error"
        }

        return truncated(description, limit: 120)
    }
}
