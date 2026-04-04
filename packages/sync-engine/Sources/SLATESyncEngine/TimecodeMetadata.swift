import AVFoundation
import Foundation

enum TimecodeMetadata {
    static func read(from url: URL, fps: Double) async -> TimecodeInfo? {
        if let sidecar = readSidecar(from: url, fps: fps) {
            return sidecar
        }
        return await readLooseAssetMetadata(from: url, fps: fps)
    }

    private static func readSidecar(from url: URL, fps: Double) -> TimecodeInfo? {
        let candidates = [
            url.deletingPathExtension().appendingPathExtension("timecode.json"),
            url.appendingPathExtension("timecode.json")
        ]

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            guard let data = try? Data(contentsOf: candidate),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let sidecarFPS = json["fps"] as? Double ?? fps
            let dropFrame = json["dropFrame"] as? Bool

            if let startSeconds = json["startSeconds"] as? Double {
                return TimecodeInfo(startSeconds: startSeconds)
            }

            if let startFrames = json["startFrames"] as? Double {
                return TimecodeInfo(startSeconds: startFrames / sidecarFPS)
            }

            if let timecode = json["timecode"] as? String,
               let seconds = parseTimecode(timecode, fps: sidecarFPS, dropFrameOverride: dropFrame) {
                return TimecodeInfo(startSeconds: seconds)
            }
        }

        return nil
    }

    private static func readLooseAssetMetadata(from url: URL, fps: Double) async -> TimecodeInfo? {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.metadata)) ?? []
        for item in metadata {
            if let value = try? await item.load(.stringValue),
               let seconds = parseTimecode(value, fps: fps) {
                return TimecodeInfo(startSeconds: seconds)
            }
        }
        return nil
    }

    static func parseTimecode(_ raw: String, fps: Double, dropFrameOverride: Bool? = nil) -> Double? {
        let normalized = raw.replacingOccurrences(of: ";", with: ":").replacingOccurrences(of: ".", with: ":")
        let pieces = normalized.split(separator: ":").map(String.init)
        guard pieces.count == 4,
              let hours = Double(pieces[0]),
              let minutes = Double(pieces[1]),
              let seconds = Double(pieces[2]),
              let frames = Double(pieces[3])
        else {
            return nil
        }

        let dropFrame = dropFrameOverride ?? raw.contains(";") || raw.contains(".")
        let roundedFPS = nominalFrameRate(for: fps)

        if dropFrame, fps >= 29, roundedFPS >= 30 {
            let totalMinutes = Int((hours * 60) + minutes)
            let dropFrames = Int(round(Double(roundedFPS) * 0.0666666667))
            let totalFrames = ((Int(hours) * 3_600 + Int(minutes) * 60 + Int(seconds)) * roundedFPS + Int(frames))
                - dropFrames * (totalMinutes - totalMinutes / 10)
            return Double(totalFrames) / fps
        }

        return (hours * 3_600) + (minutes * 60) + seconds + (frames / Double(roundedFPS))
    }

    private static func nominalFrameRate(for fps: Double) -> Int {
        switch fps {
        case ..<24.5:
            return 24
        case ..<29.5:
            return 25
        case ..<49:
            return 30
        case ..<55:
            return 50
        default:
            return 60
        }
    }
}
