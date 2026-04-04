import Foundation
import XCTest
@testable import ExportWriters
@testable import SLATESharedTypes

final class ExportPerformanceTests: XCTestCase {
    func testFCPXMLExportBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SLATE_RUN_BENCHMARKS"] == "1" else {
            return
        }

        let context = makeBenchmarkContext()
        let writer = ExportWriterFactory.writer(for: .fcpxml)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let start = ContinuousClock.now
        _ = try writer.export(context: context, to: outputDirectory)
        let duration = start.duration(to: .now)
        let elapsed = Double(duration.components.seconds)
            + (Double(duration.components.attoseconds) / 1_000_000_000_000_000_000)

        XCTAssertLessThan(elapsed, 3.0)
    }

    private func makeBenchmarkContext() -> ExportContext {
        let clips = (1...100).map { index in
            Clip(
                id: "clip-\(index)",
                projectId: "benchmark-project",
                checksum: String(repeating: "e", count: 64),
                sourcePath: "/tmp/clip-\(index).mov",
                sourceSize: 2048,
                sourceFormat: .proRes422HQ,
                sourceFps: 24,
                sourceTimecodeStart: "01:00:00:00",
                duration: 6,
                proxyPath: "/tmp/clip-\(index)_proxy.mov",
                proxyStatus: .ready,
                narrativeMeta: .init(sceneNumber: "\(max(1, index / 10))", shotCode: "A", takeNumber: index, cameraId: "A"),
                audioTracks: [
                    .init(trackIndex: 0, role: .boom, channelLabel: "Boom", sampleRate: 48_000, bitDepth: 24)
                ],
                syncedAudioPath: "/tmp/clip-\(index)_sync.wav",
                reviewStatus: index.isMultiple(of: 4) ? .circled : .unreviewed,
                projectMode: .narrative
            )
        }

        let assembly = Assembly(
            id: "benchmark-assembly",
            projectId: "benchmark-project",
            name: "Benchmark Export",
            mode: .narrative,
            clips: clips.enumerated().map { index, clip in
                AssemblyClip(
                    clipId: clip.id,
                    inPoint: 0,
                    outPoint: 4,
                    role: .primary,
                    sceneLabel: "S\(index + 1)"
                )
            },
            version: 1
        )

        return ExportContext(
            assembly: assembly,
            clipsById: Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) }),
            projectName: "Benchmark Project"
        )
    }
}
