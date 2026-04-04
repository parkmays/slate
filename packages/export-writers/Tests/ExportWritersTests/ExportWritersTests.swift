import Foundation
import Testing
@testable import ExportWriters
@testable import SLATESharedTypes

@Suite("ExportWriters")
struct ExportWritersTests {
    @Test("Assembly archive writer emits assembly snapshot JSON")
    func assemblyArchiveExport() throws {
        let context = makeNarrativeContext()
        let writer = ExportWriterFactory.writer(for: .assemblyArchive)
        let artifact = try exportArtifact(writer: writer, context: context)
        let data = try Data(contentsOf: URL(fileURLWithPath: artifact.filePath))
        let decoded = try JSONDecoder().decode(AssemblyArchivePayload.self, from: data)

        #expect(decoded.assembly.name == "Scene 10 Selects")
        #expect(decoded.clips.count == 2)
        #expect(decoded.clips.first?.annotations.first?.body == "Good line read")
    }

    @Test("FCPXML export includes keywords, markers, and audio roles")
    func fcpxmlExport() throws {
        let context = makeNarrativeContext()
        let writer = ExportWriterFactory.writer(for: .fcpxml)
        try writer.dryRun(context: context)

        let artifact = try exportArtifact(writer: writer, context: context)
        let xml = try String(contentsOf: URL(fileURLWithPath: artifact.filePath))

        #expect(xml.contains("<fcpxml version=\"1.11\">"))
        #expect(xml.contains("value=\"Circled\""))
        #expect(xml.contains("Good line read"))
        #expect(xml.contains("dialogue.boom"))
        #expect(xml.contains("dialogue.lav"))
    }

    @Test("CMX 3600 EDL export includes FROM CLIP NAME comments and reel names")
    func edlExport() throws {
        let context = makeNarrativeContext()
        let writer = ExportWriterFactory.writer(for: .cmx3600EDL)
        try writer.dryRun(context: context)

        let artifact = try exportArtifact(writer: writer, context: context)
        let edl = try String(contentsOf: URL(fileURLWithPath: artifact.filePath))

        #expect(edl.contains("TITLE: Scene 10 Selects"))
        #expect(edl.contains("FROM CLIP NAME: A001_C001.mov"))
        #expect(edl.contains("REVIEW STATUS: Circled"))
        #expect(edl.contains("LOC:"))
    }

    @Test("Premiere XML export includes scene bins, markers, and Essential Sound metadata")
    func premiereXMLExport() throws {
        let context = makeNarrativeContext()
        let writer = ExportWriterFactory.writer(for: .premiereXML)
        try writer.dryRun(context: context)

        let artifact = try exportArtifact(writer: writer, context: context)
        let xml = try String(contentsOf: URL(fileURLWithPath: artifact.filePath))

        #expect(xml.contains("<xmeml version=\"5\">"))
        #expect(xml.contains("<name>Scene 10</name>"))
        #expect(xml.contains("essentialSoundRole"))
        #expect(xml.contains("Good line read"))
    }

    @Test("Resolve XML export includes subject bins, smart bins, and color flags")
    func resolveXMLExport() throws {
        let context = makeDocumentaryContext()
        let writer = ExportWriterFactory.writer(for: .davinciResolveXML)
        try writer.dryRun(context: context)

        let artifact = try exportArtifact(writer: writer, context: context)
        let xml = try String(contentsOf: URL(fileURLWithPath: artifact.filePath))

        #expect(xml.contains("<name>Jamie Rivera</name>"))
        #expect(xml.contains("Circled Takes"))
        #expect(xml.contains("Needs Review"))
        #expect(xml.contains("Green"))
        #expect(xml.contains("A1 boom"))
    }

    @Test("AAF export preserves track layout and relink paths")
    func aafExport() throws {
        let context = makeNarrativeContext()
        let writer = ExportWriterFactory.writer(for: .aaf)
        try writer.dryRun(context: context)

        let artifact = try exportArtifact(writer: writer, context: context)
        let inspection = try AAFBridge.inspect(fileAt: URL(fileURLWithPath: artifact.filePath))

        #expect(inspection.topLevelName.contains("Scene 10 Selects"))
        #expect(inspection.slotNames == ["V1", "A1 Boom", "A2 Boom-R", "A3 Lav 1", "A4 Lav 2"])
        #expect(inspection.masterMobNames.contains("A001_C001_proxy"))
        #expect(inspection.locatorURLs.contains(URL(fileURLWithPath: "/tmp/A001_C001_proxy.mov").absoluteString))
        #expect(inspection.locatorURLs.contains(URL(fileURLWithPath: "/tmp/A001_C001_sync.wav").absoluteString))
    }

    private func exportArtifact(writer: any ExportWriter, context: ExportContext) throws -> ExportArtifact {
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try writer.export(context: context, to: outputDirectory)
    }

    private func makeNarrativeContext() -> ExportContext {
        let clipOne = Clip(
            id: "clip-1",
            projectId: "project-1",
            checksum: String(repeating: "a", count: 64),
            sourcePath: "/tmp/A001_C001.mov",
            sourceSize: 1024,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 8,
            proxyPath: "/tmp/A001_C001_proxy.mov",
            proxyStatus: .ready,
            narrativeMeta: .init(sceneNumber: "10", shotCode: "A", takeNumber: 1, cameraId: "A"),
            audioTracks: [
                .init(trackIndex: 0, role: .boom, channelLabel: "Boom L", sampleRate: 48_000, bitDepth: 24),
                .init(trackIndex: 1, role: .boom, channelLabel: "Boom R", sampleRate: 48_000, bitDepth: 24),
                .init(trackIndex: 2, role: .lav, channelLabel: "Lav 1", sampleRate: 48_000, bitDepth: 24),
                .init(trackIndex: 3, role: .lav, channelLabel: "Lav 2", sampleRate: 48_000, bitDepth: 24)
            ],
            syncResult: .init(confidence: .high, method: .timecode, offsetFrames: 0, driftPPM: 0),
            syncedAudioPath: "/tmp/A001_C001_sync.wav",
            reviewStatus: .circled,
            annotations: [
                Annotation(
                    userId: "u1",
                    userDisplayName: "Alex",
                    timecodeIn: "01:00:02:00",
                    body: "Good line read"
                )
            ],
            projectMode: .narrative
        )

        let clipTwo = Clip(
            id: "clip-2",
            projectId: "project-1",
            checksum: String(repeating: "b", count: 64),
            sourcePath: "/tmp/A001_C002.mov",
            sourceSize: 1024,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:08:00",
            duration: 6,
            proxyPath: "/tmp/A001_C002_proxy.mov",
            proxyStatus: .ready,
            narrativeMeta: .init(sceneNumber: "10", shotCode: "B", takeNumber: 2, cameraId: "A"),
            audioTracks: [
                .init(trackIndex: 0, role: .mix, channelLabel: "Mix", sampleRate: 48_000, bitDepth: 24)
            ],
            syncResult: .init(confidence: .medium, method: .waveformCorrelation, offsetFrames: 2, driftPPM: 0),
            syncedAudioPath: "/tmp/A001_C002_sync.wav",
            reviewStatus: .flagged,
            annotations: [
                Annotation(
                    userId: "u2",
                    userDisplayName: "Jordan",
                    timecodeIn: "01:00:09:12",
                    body: "Check eyeline"
                )
            ],
            projectMode: .narrative
        )

        let assembly = Assembly(
            id: "assembly-1",
            projectId: "project-1",
            name: "Scene 10 Selects",
            mode: .narrative,
            clips: [
                AssemblyClip(clipId: clipOne.id, inPoint: 0, outPoint: 8, role: .primary, sceneLabel: "10A"),
                AssemblyClip(clipId: clipTwo.id, inPoint: 1, outPoint: 5, role: .primary, sceneLabel: "10B")
            ],
            version: 3
        )

        return ExportContext(
            assembly: assembly,
            clipsById: [
                clipOne.id: clipOne,
                clipTwo.id: clipTwo
            ],
            projectName: "Pilot Episode"
        )
    }

    private func makeDocumentaryContext() -> ExportContext {
        let clip = Clip(
            id: "doc-clip-1",
            projectId: "project-doc-1",
            checksum: String(repeating: "d", count: 64),
            sourcePath: "/tmp/INT_001.mov",
            sourceSize: 4096,
            sourceFormat: .proRes422HQ,
            sourceFps: 23.976,
            sourceTimecodeStart: "01:00:00:00",
            duration: 12,
            proxyPath: "/tmp/INT_001_proxy.mov",
            proxyStatus: .ready,
            documentaryMeta: .init(
                subjectName: "Jamie Rivera",
                subjectId: "subject-1",
                shootingDay: 2,
                sessionLabel: "Interview",
                location: "Studio",
                topicTags: ["Origins"]
            ),
            audioTracks: [
                .init(trackIndex: 0, role: .boom, channelLabel: "Boom", sampleRate: 48_000, bitDepth: 24)
            ],
            syncedAudioPath: "/tmp/INT_001_sync.wav",
            reviewStatus: .circled,
            annotations: [
                Annotation(
                    userId: "u3",
                    userDisplayName: "Morgan",
                    timecodeIn: "01:00:03:12",
                    body: "Strong quote"
                )
            ],
            projectMode: .documentary
        )

        let assembly = Assembly(
            id: "assembly-doc-1",
            projectId: "project-doc-1",
            name: "Jamie Interview Selects",
            mode: .documentary,
            clips: [
                AssemblyClip(clipId: clip.id, inPoint: 0, outPoint: 10, role: .interview, sceneLabel: "Jamie")
            ],
            version: 1
        )

        return ExportContext(
            assembly: assembly,
            clipsById: [clip.id: clip],
            projectName: "Origins Documentary"
        )
    }
}
