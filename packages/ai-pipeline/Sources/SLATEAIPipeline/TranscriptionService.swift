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
    private typealias SpeakerSegment = (startSeconds: Double, endSeconds: Double, speakerId: String)

    public init() {}

    public func transcribe(audioURL: URL, knownSpeakers: [String] = []) async throws -> Transcript {
        let loadedAudio = try? await AudioHelpers.loadMonoSamples(from: audioURL)
        let diarizationSegments: [SpeakerSegment]
        if let loadedAudio {
            let resampled = resampleSamples(loadedAudio.samples, from: loadedAudio.sampleRate, to: 16_000)
            diarizationSegments = diarizeSpeakers(samples: resampled.samples, sampleRate: resampled.sampleRate)
        } else {
            diarizationSegments = []
        }

        #if canImport(Speech)
        if let recognized = try await transcribeWithSpeechFramework(audioURL: audioURL),
           !recognized.words.isEmpty || !recognized.text.isEmpty {
            return Transcript(
                text: recognized.text,
                language: recognized.language,
                words: mapKnownSpeakerNames(
                    words: assignSpeakerLabels(words: recognized.words, segments: diarizationSegments),
                    knownSpeakers: knownSpeakers
                )
            )
        }
        #endif

        return try await heuristicTranscript(
            audioURL: audioURL,
            preloadedAudio: loadedAudio,
            diarizationSegments: diarizationSegments,
            knownSpeakers: knownSpeakers
        )
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
                        text: segment.confidence < 0.5 ? "[inaudible]" : segment.substring
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

    private func heuristicTranscript(
        audioURL: URL,
        preloadedAudio: (samples: [Float], sampleRate: Double, channels: Int)?,
        diarizationSegments: [SpeakerSegment],
        knownSpeakers: [String]
    ) async throws -> Transcript {
        let loaded: (samples: [Float], sampleRate: Double, channels: Int)
        if let preloadedAudio {
            loaded = preloadedAudio
        } else {
            loaded = try await AudioHelpers.loadMonoSamples(from: audioURL)
        }
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

        for segment in segments {
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
            let descriptor = describeSegment(utteranceSamples, duration: duration)
            phraseTitles.append(descriptor)

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

        words = mapKnownSpeakerNames(
            words: assignSpeakerLabels(words: words, segments: diarizationSegments),
            knownSpeakers: knownSpeakers
        )

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

    private func describeSegment(_ samples: [Float], duration: Double) -> String {
        let rms = AudioHelpers.rms(samples)
        let energyDescriptor: String
        switch rms {
        case ..<0.05:
            energyDescriptor = "low energy"
        case ..<0.14:
            energyDescriptor = "moderate energy"
        default:
            energyDescriptor = "high energy"
        }
        return String(format: "spoken (%.1fs, %@)", duration, energyDescriptor)
    }

    private func resampleSamples(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> (samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, sourceRate > 0, targetRate > 0 else {
            return (samples, sourceRate)
        }
        guard abs(sourceRate - targetRate) > 0.001 else {
            return (samples, sourceRate)
        }

        let targetCount = max(1, Int((Double(samples.count) * targetRate / sourceRate).rounded()))
        var resampled = Array(repeating: Float.zero, count: targetCount)
        let maxIndex = samples.count - 1
        for index in 0..<targetCount {
            let position = Double(index) * sourceRate / targetRate
            let lower = min(maxIndex, Int(position.rounded(.down)))
            let upper = min(maxIndex, lower + 1)
            let fraction = Float(position - Double(lower))
            let lowerSample = samples[lower]
            let upperSample = samples[upper]
            resampled[index] = lowerSample + ((upperSample - lowerSample) * fraction)
        }

        return (resampled, targetRate)
    }

    private func diarizeSpeakers(samples: [Float], sampleRate: Double) -> [SpeakerSegment] {
        guard !samples.isEmpty, sampleRate > 0 else {
            return []
        }

        let frameSize = max(16, Int((0.025 * sampleRate).rounded()))
        let hopSize = max(8, Int((0.010 * sampleRate).rounded()))
        guard samples.count >= frameSize else {
            let duration = Double(samples.count) / sampleRate
            return [(0, max(duration, 0.01), "Speaker A")]
        }

        var rmsValues: [Double] = []
        var centroids: [Double] = []
        var frameStarts: [Double] = []
        var index = 0
        while index + frameSize <= samples.count {
            let frame = Array(samples[index..<(index + frameSize)])
            rmsValues.append(AudioHelpers.rms(frame))
            _ = AudioHelpers.zeroCrossingRate(frame)
            centroids.append(computeSpectralCentroid(frame: frame, sampleRate: sampleRate))
            frameStarts.append(Double(index) / sampleRate)
            index += hopSize
        }

        guard !rmsValues.isEmpty else {
            let duration = Double(samples.count) / sampleRate
            return [(0, max(duration, 0.01), "Speaker A")]
        }

        let windowFrames = max(1, Int((0.200 / 0.010).rounded()))
        let minSegmentFrames = max(1, Int((0.300 / 0.010).rounded()))
        let maxSpeakers = 4

        var speakerIndex = 0
        var segmentStartFrame = 0
        var segments: [SpeakerSegment] = []

        for frameIndex in 1..<rmsValues.count {
            let previousCentroid = centroids[frameIndex - 1]
            let currentCentroid = centroids[frameIndex]
            guard previousCentroid > 1 else { continue }
            let centroidShift = abs(currentCentroid - previousCentroid) / previousCentroid

            let windowStart = max(0, frameIndex - windowFrames + 1)
            let localMax = rmsValues[windowStart...frameIndex].max() ?? 0
            let dipThreshold = localMax * 0.4
            let hasEnergyDip = localMax > 0 && rmsValues[frameIndex] <= dipThreshold

            if centroidShift > 0.15 && hasEnergyDip && (frameIndex - segmentStartFrame) >= minSegmentFrames {
                let startSeconds = frameStarts[segmentStartFrame]
                let endSeconds = frameStarts[frameIndex]
                let label = "Speaker \(String(UnicodeScalar(65 + speakerIndex)!))"
                if endSeconds > startSeconds {
                    segments.append((startSeconds, endSeconds, label))
                }
                speakerIndex = min(speakerIndex + 1, maxSpeakers - 1)
                segmentStartFrame = frameIndex
            }
        }

        let duration = Double(samples.count) / sampleRate
        let finalStart = frameStarts[min(segmentStartFrame, frameStarts.count - 1)]
        let finalLabel = "Speaker \(String(UnicodeScalar(65 + speakerIndex)!))"
        if duration > finalStart {
            segments.append((finalStart, duration, finalLabel))
        }

        if segments.isEmpty {
            return [(0, max(duration, 0.01), "Speaker A")]
        }
        return segments
    }

    private func computeSpectralCentroid(frame: [Float], sampleRate: Double) -> Double {
        let magnitudes = AudioHelpers.computeFFTMagnitudes(frame: frame)
        guard magnitudes.count > 1 else { return 0 }
        let fftSize = magnitudes.count * 2
        var weightedSum = 0.0
        var magnitudeSum = 0.0
        for (index, magnitude) in magnitudes.enumerated() {
            let frequency = (Double(index) * sampleRate) / Double(fftSize)
            let magnitudeValue = Double(magnitude)
            weightedSum += frequency * magnitudeValue
            magnitudeSum += magnitudeValue
        }
        guard magnitudeSum > 0 else { return 0 }
        return weightedSum / magnitudeSum
    }

    private func assignSpeakerLabels(words: [TranscriptWord], segments: [SpeakerSegment]) -> [TranscriptWord] {
        guard !words.isEmpty else { return [] }
        guard !segments.isEmpty else {
            return words.map { word in
                TranscriptWord(start: word.start, end: word.end, text: word.text, speaker: "Speaker A")
            }
        }

        return words.map { word in
            let midpoint = (word.start + word.end) * 0.5
            let matched = segments.first { segment in
                midpoint >= segment.startSeconds && midpoint <= segment.endSeconds
            } ?? segments.min(by: { left, right in
                let leftDistance = min(abs(midpoint - left.startSeconds), abs(midpoint - left.endSeconds))
                let rightDistance = min(abs(midpoint - right.startSeconds), abs(midpoint - right.endSeconds))
                return leftDistance < rightDistance
            })
            return TranscriptWord(
                start: word.start,
                end: word.end,
                text: word.text,
                speaker: matched?.speakerId ?? "Speaker A"
            )
        }
    }

    private func mapKnownSpeakerNames(words: [TranscriptWord], knownSpeakers: [String]) -> [TranscriptWord] {
        let normalized = knownSpeakers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else {
            return words
        }

        var discovered: [String] = []
        for word in words {
            guard let speaker = word.speaker, !speaker.isEmpty else { continue }
            if !discovered.contains(speaker) {
                discovered.append(speaker)
            }
        }
        guard !discovered.isEmpty else {
            return words
        }

        var mapping: [String: String] = [:]
        for (index, speakerId) in discovered.enumerated() {
            if index < normalized.count {
                mapping[speakerId] = normalized[index]
            }
        }

        return words.map { word in
            guard let speaker = word.speaker, let mapped = mapping[speaker] else {
                return word
            }
            return TranscriptWord(start: word.start, end: word.end, text: word.text, speaker: mapped)
        }
    }
}
