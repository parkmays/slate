import ExportWriters
import SLATEAIPipeline
import SLATESharedTypes
import SLATESyncEngine
import Testing

/// Cross-package smoke tests — verifies the unified `Package.swift` graph resolves and links.
@Suite("SLATEIntegrationTests")
struct MonorepoIntegrationTests {
    @Test("Core engine types and export factory are reachable from one test bundle")
    func monorepoLinkSmoke() {
        let classifier = AudioRoleClassifier()
        _ = classifier

        let vision = VisionScorerOptimized()
        _ = vision

        let writer = ExportWriterFactory.writer(for: .assemblyArchive)
        #expect(writer.format == .assemblyArchive)
    }
}
