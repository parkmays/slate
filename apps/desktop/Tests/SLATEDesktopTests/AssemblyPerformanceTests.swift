import Foundation
import XCTest
@testable import SLATECore
@testable import SLATESharedTypes

final class AssemblyPerformanceTests: XCTestCase {
    func testAssemblyPerformanceBenchmark() {
        guard ProcessInfo.processInfo.environment["SLATE_RUN_BENCHMARKS"] == "1" else {
            return
        }

        let project = Project(id: "benchmark-project", name: "Benchmark", mode: .narrative)
        let clips = makeBenchmarkClips()
        let engine = AssemblyEngine()

        let start = ContinuousClock.now
        let assembly = engine.buildAssembly(project: project, clips: clips)
        let duration = start.duration(to: .now)
        let elapsed = Double(duration.components.seconds)
            + (Double(duration.components.attoseconds) / 1_000_000_000_000_000_000)

        XCTAssertEqual(assembly.clips.count, 50)
        XCTAssertLessThan(elapsed, 5.0)
    }

    private func makeBenchmarkClips() -> [Clip] {
        let scoredAt = ISO8601DateFormatter().string(from: Date())
        return (1...10).flatMap { scene in
            (1...5).flatMap { setup in
                (1...3).map { take in
                    let id = "\(scene)-\(setup)-\(take)"
                    return Clip(
                        id: id,
                        projectId: "benchmark-project",
                        checksum: String(repeating: "c", count: 64),
                        sourcePath: "/tmp/\(id).mov",
                        sourceSize: 10_240,
                        sourceFormat: .proRes422HQ,
                        sourceFps: 24,
                        sourceTimecodeStart: "01:00:00:00",
                        duration: 9,
                        narrativeMeta: .init(
                            sceneNumber: "\(scene)",
                            shotCode: String(UnicodeScalar(64 + setup)!),
                            takeNumber: take,
                            cameraId: "A"
                        ),
                        aiScores: AIScores(
                            composite: Double(scene * setup * take),
                            focus: 70,
                            exposure: 70,
                            stability: 70,
                            audio: 70,
                            scoredAt: scoredAt,
                            modelVersion: "benchmark"
                        ),
                        reviewStatus: take == 3 ? .circled : .unreviewed,
                        projectMode: .narrative
                    )
                }
            }
        }
    }
}
