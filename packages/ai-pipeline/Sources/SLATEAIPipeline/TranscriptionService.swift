import Foundation
import SLATESharedTypes
#if canImport(Speech)
import Speech
#endif

public struct TranscriptWord: Codable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
    public let speaker: String?

    public init(start: Double, end: Double, text: String, speaker: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

public struct Transcript: Codable, Sendable {
    public let text: String
    public let language: String?
    public let words: [TranscriptWord]

    public init(text: String, language: String? = nil, words: [TranscriptWord] = []) {
        self.text = text
        self.language = language
        self.words = words
    }
}

public struct TranscriptionService: Sendable {
    public init() {}

    public func transcribe(audioURL: URL) async throws -> Transcript {
        #if canImport(Speech)
        if let recognized = try await transcribeWithSpeechFramework(audioURL: audioURL),
           !recognized.words.isEmpty || !recognized.text.isEmpty {
            return recognized
        }
        #endif

        return try await heuristicTranscript(audioURL: audioURL)
    }

    #if canImport(Speech)
    private func transcribeWithSpeechFramework(audioURL: URL) async throws -> Transcript? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return nil
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer(),
              recognizer.supportsOnDeviceRecognition else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            final class RecognitionBox: @unchecked Sendable {
                var task: SFSpeechRecognitionTask?
                var resumed = false
            }

            let box = RecognitionBox()
            box.task = recognizer.recognitionTask(with: request) { result, error in
                if box.resumed {
                    return
                }

                if let error {
                    box.resumed = true
                    box.task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let words = result.bestTranscription.segments.map { segment in
                    TranscriptWord(
                        start: segment.timestamp,
                        end: segment.timestamp + segment.duration,
                        text: segment.substring
                    )
                }
                let transcript = Transcript(
                    text: result.bestTranscription.formattedString,
                    language: recognizer.locale.identifier,
                    words: words
                )
                box.resumed = true
                box.task?.cancel()
                continuation.resume(returning: transcript)
            }
        }
    }
    #endif

    private func heuristicTranscript(audioURL: URL) async throws -> Transcript {
        let loaded = try await AudioHelpers.loadMonoSamples(from: audioURL)
        guard !loaded.samples.isEmpty else {
            return Transcript(text: "", language: nil, words: [])
        }

        let sampleRate = loaded.sampleRate
        let envelopeRate = 40.0
        let absolute = loaded.samples.map(abs)
        let coarse = AudioHelpers.downsample(absolute, from: sampleRate, to: envelopeRate)
        let smoothed = AudioHelpers.movingAverage(coarse, windowSize: 5)
        guard !smoothed.isEmpty else {
            return Transcript(text: "", language: nil, words: [])
        }

        let floor = Double(AudioHelpers.percentile(smoothed, percentile: 0.2))
        let ceiling = Double(AudioHelpers.percentile(smoothed, percentile: 0.95))
        let adaptiveThreshold = max(floor * 2.2, min(ceiling * 0.45, 0.04))
        let activation = Float(max(adaptiveThreshold, 0.008))
        let release = activation * 0.7
        let minFrames = Int(0.30 * envelopeRate)
        let minGapFrames = Int(0.18 * envelopeRate)

        var segments: [(start: Int, end: Int)] = []
        var currentStart: Int?
        var trailingSilence = 0

        for (index, value) in smoothed.enumerated() {
            if value >= activation {
                if currentStart == nil {
                    currentStart = index
                }
                trailingSilence = 0
            } else if let start = currentStart {
                if value > release {
                    trailingSilence = 0
                    continue
                }

                trailingSilence += 1
                if trailingSilence >= minGapFrames {
                    let end = max(start, index - trailingSilence)
                    if end - start + 1 >= minFrames {
                        segments.append((start, end))
                    }
                    currentStart = nil
                    trailingSilence = 0
                }
            }
        }

        if let start = currentStart {
            let end = smoothed.count - 1
            if end - start + 1 >= minFrames {
                segments.append((start, end))
            }
        }

        guard !segments.isEmpty else {
            return Transcript(text: "", language: nil, words: [])
        }

        var words: [TranscriptWord] = []
        var phraseTitles: [String] = []
        let secondsPerFrame = 1.0 / envelopeRate

        for (index, segment) in segments.enumerated() {
            let startSeconds = Double(segment.start) * secondsPerFrame
            let endSeconds = Double(segment.end + 1) * secondsPerFrame
            let duration = max(endSeconds - startSeconds, 0.25)
            let wordCount = max(1, Int((duration / 0.55).rounded()))
            let utteranceSamples = slice(
                loaded.samples,
                sampleRate: sampleRate,
                startSeconds: startSeconds,
                endSeconds: endSeconds
            )
            let descriptor = describeSegment(utteranceSamples)
            phraseTitles.append("\(descriptor) passage \(index + 1)")

            for tokenIndex in 0..<wordCount {
                let tokenStart = startSeconds + (duration * Double(tokenIndex) / Double(wordCount))
                let tokenEnd = startSeconds + (duration * Double(tokenIndex + 1) / Double(wordCount))
                let tokenText = tokenIndex == 0 ? descriptor : "phrase"
                words.append(
                    TranscriptWord(
                        start: tokenStart,
                        end: tokenEnd,
                        text: tokenText
                    )
                )
            }
        }

        return Transcript(
            text: phraseTitles.joined(separator: ". "),
            language: "und",
            words: words
        )
    }

    private func slice(_ samples: [Float], sampleRate: Double, startSeconds: Double, endSeconds: Double) -> [Float] {
        let start = max(0, Int((startSeconds * sampleRate).rounded(.down)))
        let end = min(samples.count, Int((endSeconds * sampleRate).rounded(.up)))
        guard start < end else {
            return []
        }
        return Array(samples[start..<end])
    }

    private func describeSegment(_ samples: [Float]) -> String {
        let rms = AudioHelpers.rms(samples)
        let zeroCrossings = AudioHelpers.zeroCrossingRate(samples)

        if rms > 0.17 {
            return zeroCrossings > 0.18 ? "animated" : "emphatic"
        }
        if zeroCrossings < 0.08 {
            return "steady"
        }
        return "spoken"
    }
}
