import Foundation
import SLATESharedTypes

public struct AudioScoreResult: Sendable {
    public let audio: Double
    public let reasons: [ScoreReason]

    public init(audio: Double, reasons: [ScoreReason]) {
        self.audio = audio
        self.reasons = reasons
    }
}

public struct AudioScorer: Sendable {
    public init() {}

    public func scoreAudio(syncedAudioURL: URL) async throws -> AudioScoreResult {
        let loaded = try await AudioHelpers.loadMonoSamples(from: syncedAudioURL)
        guard !loaded.samples.isEmpty else {
            return AudioScoreResult(
                audio: 0,
                reasons: [
                    .init(
                        dimension: "audio",
                        score: 0,
                        flag: .warning,
                        message: "No audio samples were available for scoring."
                    )
                ]
            )
        }

        let absolute = loaded.samples.map(abs)
        let peak = absolute.max() ?? 0
        let clippingRatio = Double(absolute.filter { $0 >= 0.98 }.count) / Double(absolute.count)
        let rms = Self.rms(loaded.samples)
        let derivative = zip(loaded.samples.dropFirst(), loaded.samples).map { abs($0.0 - $0.1) }
        let airiness = derivative.isEmpty ? 0 : Self.rms(derivative) / max(rms, 0.0001)

        let levelScore = max(0, min(100, 100 - (abs(rms - 0.16) * 420)))
        let clippingScore = max(0, min(100, 100 - (clippingRatio * 12_000)))
        let noiseScore = max(0, min(100, 100 - max(0, airiness - 0.55) * 95))
        let peakPenalty = peak > 0.995 ? 12.0 : 0.0
        let audioScore = max(0, min(100, ((levelScore * 0.45) + (clippingScore * 0.35) + (noiseScore * 0.20)) - peakPenalty))

        var reasons: [ScoreReason] = []
        if clippingRatio > 0.001 {
            reasons.append(
                .init(
                    dimension: "audio",
                    score: clippingScore,
                    flag: clippingRatio > 0.0015 ? .error : .warning,
                    message: "Clipping detected in the synced audio. Inspect peaks around \(AudioHelpers.timecodeString(for: 0))."
                )
            )
        }
        if rms < 0.03 {
            reasons.append(
                .init(
                    dimension: "audio",
                    score: levelScore,
                    flag: .warning,
                    message: "Overall audio level is low and may need gain compensation."
                )
            )
        }
        if airiness > 0.95 {
            reasons.append(
                .init(
                    dimension: "audio",
                    score: noiseScore,
                    flag: .warning,
                    message: "High-frequency noise or harsh transients were detected in the audio bed."
                )
            )
        }
        if reasons.isEmpty {
            reasons.append(
                .init(
                    dimension: "audio",
                    score: audioScore,
                    flag: .info,
                    message: "Audio scored cleanly with no blocking issues."
                )
            )
        }

        return AudioScoreResult(audio: audioScore, reasons: reasons)
    }

    private static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let power = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return sqrt(power)
    }
}
