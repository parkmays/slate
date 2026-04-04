import Foundation
import Testing
@testable import SLATESharedTypes

@Suite("SLATESharedTypes")
struct SLATESharedTypesTests {
    @Test("Clip round-trips through Codable")
    func clipRoundTrip() throws {
        let clip = Clip(
            projectId: UUID().uuidString,
            checksum: String(repeating: "a", count: 64),
            sourcePath: "/tmp/clip.mov",
            sourceSize: 10_240,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 12,
            projectMode: .narrative
        )

        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        #expect(decoded.projectId == clip.projectId)
        #expect(decoded.sourceFormat == .proRes422HQ)
        #expect(decoded.projectMode == .narrative)
    }

    @Test("Assembly round-trips through Codable")
    func assemblyRoundTrip() throws {
        let assembly = Assembly(
            projectId: UUID().uuidString,
            name: "Scene 12 Selects",
            mode: .narrative,
            clips: [
                AssemblyClip(
                    clipId: UUID().uuidString,
                    inPoint: 1.25,
                    outPoint: 4.5,
                    role: .primary,
                    sceneLabel: "12A"
                )
            ],
            version: 2
        )

        let data = try JSONEncoder().encode(assembly)
        let decoded = try JSONDecoder().decode(Assembly.self, from: data)
        #expect(decoded.name == "Scene 12 Selects")
        #expect(decoded.clips.first?.sceneLabel == "12A")
        #expect(decoded.version == 2)
    }
}
