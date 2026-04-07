import Foundation
import XCTest
import SLATESharedTypes
@testable import IngestDaemon

final class IngestDaemonTests: XCTestCase {
    func testXXH64KnownVectors() {
        var emptyHasher = XXH64Hasher()
        emptyHasher.update(Data())
        XCTAssertEqual(emptyHasher.finalizeHex(), "ef46db3751d8e999")

        var helloHasher = XXH64Hasher()
        helloHasher.update(Data("hello".utf8))
        XCTAssertEqual(helloHasher.finalizeHex(), "26c7827d889f6da3")
    }

    func testVerifiedCopyEngineProducesMatchingHashesAndManifest() throws {
        let fixtureRoot = ProcessInfo.processInfo.environment["SLATE_MHL_FIXTURE_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let shouldCleanup = fixtureRoot == nil
        let tempDir = (fixtureRoot ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("slate-verified-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            if shouldCleanup {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        let sourceURL = tempDir.appendingPathComponent("source.bin")
        let destinationURL = tempDir.appendingPathComponent("dest/source.bin")
        let payload = Data((0..<65_536).map { UInt8($0 % 251) })
        try payload.write(to: sourceURL)
        let historyRoot = tempDir.appendingPathComponent("dest", isDirectory: true)
        let childAscmhlDir = historyRoot
            .appendingPathComponent("A002R2EC", isDirectory: true)
            .appendingPathComponent("ascmhl", isDirectory: true)
        try FileManager.default.createDirectory(at: childAscmhlDir, withIntermediateDirectories: true)
        let childManifestURL = childAscmhlDir.appendingPathComponent("0001_A002R2EC_2026-01-01_000000.mhl")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:ASC:MHL:v2.0 ASCMHL.xsd">
          <creatorinfo>
            <creationdate>2026-01-01T00:00:00Z</creationdate>
            <hostname>fixture</hostname>
            <tool version="1.0">fixture</tool>
          </creatorinfo>
          <processinfo><process>transfer</process></processinfo>
          <hashes><hash><path size="1">dummy.txt</path><c4 action="original">c41111111111111111111111111111111111111111111111111111111111111111111111111111111111</c4></hash></hashes>
        </hashlist>
        """.write(to: childManifestURL, atomically: true, encoding: .utf8)
        let childChainURL = childAscmhlDir.appendingPathComponent("ascmhl_chain.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <ascmhldirectory xmlns="urn:ASC:MHL:DIRECTORY:v2.0">
          <hashlist sequencenr="1">
            <path>\(childManifestURL.lastPathComponent)</path>
            <c4>c4CHILDREFERENCE11111111111111111111111111111111111111111111111111111111111111111111</c4>
          </hashlist>
        </ascmhldirectory>
        """.write(to: childChainURL, atomically: true, encoding: .utf8)

        let result = try VerifiedCopyEngine.copyAndVerify(from: sourceURL, to: destinationURL)
        XCTAssertTrue(result.isVerified)
        XCTAssertEqual(result.sourceHash, result.destinationHash)
        XCTAssertEqual(result.bytesCopied, Int64(payload.count))

        let manifestURL = try MHLManifestWriter.write(
            for: result,
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            historyRootURL: historyRoot
        )
        let manifestContents = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertTrue(manifestContents.contains("<hashlist version=\"2.0\""))
        XCTAssertTrue(manifestContents.contains("xmlns=\"urn:ASC:MHL:v2.0\""))
        XCTAssertTrue(manifestContents.contains(result.destinationHash))
        XCTAssertTrue(manifestContents.contains("<path size=\""))
        XCTAssertTrue(manifestContents.contains(">source.bin</path>"))

        let chainURL = tempDir
            .appendingPathComponent("dest", isDirectory: true)
            .appendingPathComponent("ascmhl", isDirectory: true)
            .appendingPathComponent("ascmhl_chain.xml")
        let chainContents = try String(contentsOf: chainURL, encoding: .utf8)
        XCTAssertTrue(chainContents.contains("<ascmhldirectory xmlns=\"urn:ASC:MHL:DIRECTORY:v2.0\">"))
        XCTAssertTrue(chainContents.contains("<hashlist sequencenr=\"1\">"))
        XCTAssertTrue(chainContents.contains(manifestURL.lastPathComponent))
        XCTAssertTrue(manifestContents.contains("<c4 action=\"verified\""))
        XCTAssertTrue(manifestContents.contains("<roothash>"))
        XCTAssertTrue(manifestContents.contains("<references>"))
        XCTAssertTrue(manifestContents.contains("<path>A002R2EC/ascmhl/0001_A002R2EC_2026-01-01_000000.mhl</path>"))
        XCTAssertTrue(manifestContents.contains("<c4>c4CHILDREFERENCE11111111111111111111111111111111111111111111111111111111111111111111</c4>"))
    }

    func testProxyGenerationAgainstRRBugRenders() async throws {
        guard ProcessInfo.processInfo.environment["RUN_RRBUG_PROXY_TESTS"] == "1" else {
            throw XCTSkip("Set RUN_RRBUG_PROXY_TESTS=1 to run media integration test")
        }

        let mediaRoot = ProcessInfo.processInfo.environment["RRBUG_MEDIA_DIR"]
            ?? "/Users/parker/Library/CloudStorage/Dropbox-NEA4/Parker Mays/RR BUG/RR BUG RENDERS"
        let rootURL = URL(fileURLWithPath: mediaRoot, isDirectory: true)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue, "RR BUG media path is not a directory: \(rootURL.path)")

        let maxFiles = Int(ProcessInfo.processInfo.environment["RRBUG_MAX_FILES"] ?? "2") ?? 2
        let supportedExts = Set(["mov", "mp4", "m4v", "mxf", "r3d", "ari", "arx", "braw"])
        let files = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { supportedExts.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        .prefix(maxFiles)

        XCTAssertFalse(files.isEmpty, "No supported media files found under \(rootURL.path)")

        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-proxy-rrbug-\(UUID().uuidString).db")
        let store = try GRDBStore(path: dbURL.path)
        let generator = ProxyGenerator(dbQueue: try await store.dbQueue, grdbStore: store)

        for fileURL in files {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let ext = fileURL.pathExtension.lowercased()
            let format: SourceFormat = (ext == "mov") ? .proRes422HQ : .h264
            let clip = Clip(
                projectId: "rr-bug-integration",
                checksum: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                sourcePath: fileURL.path,
                sourceSize: size,
                sourceFormat: format,
                sourceFps: 24,
                sourceTimecodeStart: "00:00:00:00",
                duration: 0,
                proxyPath: nil,
                proxyStatus: .pending,
                proxyChecksum: nil,
                narrativeMeta: .init(sceneNumber: fileURL.deletingPathExtension().lastPathComponent, shotCode: "A", takeNumber: 1, cameraId: "A"),
                documentaryMeta: nil,
                audioTracks: [],
                syncResult: .unsynced,
                syncedAudioPath: nil,
                aiScores: nil,
                transcriptId: nil,
                aiProcessingStatus: .pending,
                reviewStatus: .unreviewed,
                annotations: [],
                approvalStatus: .pending,
                approvedBy: nil,
                approvedAt: nil,
                ingestedAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                projectMode: .narrative
            )
            try await store.saveClip(clip)

            do {
                try await generator.generateProxy(for: clip, burnInConfig: BurnInConfig())
            } catch {
                XCTFail("Proxy generation failed for \(fileURL.lastPathComponent): \(error)")
            }

            let persisted = try await store.getClip(byId: clip.id)
            XCTAssertEqual(persisted?.proxyStatus, .ready, "Expected ready for \(fileURL.lastPathComponent)")
            XCTAssertNotNil(persisted?.proxyPath, "Expected proxy path for \(fileURL.lastPathComponent)")
        }
    }

    func testBurnInTimecodeStringAdvancesByFrameRate() {
        let r = BurnInRenderer()
        XCTAssertEqual(r.timecodeString(startTC: "01:00:00:00", frameNumber: 0, fps: 24), "01:00:00:00")
        XCTAssertEqual(r.timecodeString(startTC: "01:00:00:00", frameNumber: 24, fps: 24), "01:00:01:00")

        let fps23976 = 24_000.0 / 1001.0
        XCTAssertEqual(r.timecodeString(startTC: "01:00:00:00", frameNumber: 24, fps: fps23976), "01:00:01:00")

        XCTAssertEqual(r.timecodeString(startTC: "00:00:00:20", frameNumber: 5, fps: 25), "00:00:01:00")

        let fps2997 = 30_000.0 / 1001.0
        XCTAssertEqual(r.timecodeString(startTC: "00:00:00:29", frameNumber: 1, fps: fps2997), "00:00:01:00")

        XCTAssertEqual(r.timecodeString(startTC: "00:00:00:00", frameNumber: 30, fps: 30), "00:00:01:00")
    }

    func testGRDBStorePersistsSyncAndAIScoreUpdates() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-ingest-\(UUID().uuidString).db")
        let store = try GRDBStore(path: databaseURL.path)

        let clip = Clip(
            projectId: UUID().uuidString,
            checksum: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            sourcePath: "/tmp/source.mov",
            sourceSize: 1_024,
            sourceFormat: .proRes422HQ,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 10,
            proxyPath: nil,
            proxyStatus: .pending,
            proxyChecksum: nil,
            narrativeMeta: .init(sceneNumber: "1", shotCode: "A", takeNumber: 1, cameraId: "A"),
            documentaryMeta: nil,
            audioTracks: [],
            syncResult: .unsynced,
            syncedAudioPath: nil,
            aiScores: nil,
            transcriptId: nil,
            aiProcessingStatus: .pending,
            reviewStatus: .unreviewed,
            annotations: [],
            approvalStatus: .pending,
            approvedBy: nil,
            approvedAt: nil,
            ingestedAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            projectMode: .narrative
        )

        try await store.saveClip(clip)

        let audioTracks = [
            AudioTrack(trackIndex: 0, role: .boom, channelLabel: "boom", sampleRate: 48_000, bitDepth: 24)
        ]
        let syncResult = SyncResult(confidence: .high, method: .timecode, offsetFrames: 0)
        try await store.updateAudioSync(
            clipId: clip.id,
            audioTracks: audioTracks,
            syncResult: syncResult,
            syncedAudioPath: "/tmp/boom.wav"
        )

        let aiScores = AIScores(
            composite: 82,
            focus: 80,
            exposure: 81,
            stability: 84,
            audio: 83,
            performance: nil,
            contentDensity: nil,
            scoredAt: ISO8601DateFormatter().string(from: Date()),
            modelVersion: "test",
            reasoning: [
                ScoreReason(dimension: "focus", score: 80, flag: .info, message: "fixture")
            ]
        )
        try await store.updateAIScores(clipId: clip.id, aiScores: aiScores, status: .ready)

        let persisted = try await store.getClip(byId: clip.id)
        XCTAssertEqual(persisted?.audioTracks, audioTracks)
        XCTAssertEqual(persisted?.syncResult, syncResult)
        XCTAssertEqual(persisted?.syncedAudioPath, "/tmp/boom.wav")
        XCTAssertEqual(persisted?.aiScores, aiScores)
        XCTAssertEqual(persisted?.aiProcessingStatus, .ready)
    }

    func testBundledProxyLUTsExistAndHaveExpectedCubeShape() throws {
        let expectedLUTs: [ProxyLUT] = [
            .arriLogC3Rec709,
            .bmFilmGen5Rec709,
            .redIPP2Rec709
        ]

        for lut in expectedLUTs {
            guard let url = LUTManager.bundledLUTURL(for: lut) else {
                XCTFail("Missing bundled LUT for \(lut.rawValue)")
                continue
            }

            let contents = try String(contentsOf: url, encoding: .utf8)
            let allLines = contents.components(separatedBy: .newlines)

            let dimensionLine = allLines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("LUT_3D_SIZE") }
            XCTAssertEqual(dimensionLine?.trimmingCharacters(in: .whitespaces), "LUT_3D_SIZE 33")

            let dataLineCount = allLines.reduce(into: 0) { partial, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                guard !trimmed.hasPrefix("#") else { return }
                guard !trimmed.hasPrefix("LUT_3D_SIZE") else { return }
                guard !trimmed.hasPrefix("TITLE") else { return }
                guard !trimmed.hasPrefix("DOMAIN") else { return }
                partial += 1
            }
            XCTAssertEqual(dataLineCount, 33 * 33 * 33, "Unexpected data line count for \(lut.rawValue)")
        }
    }

    func testScriptImporterParsesMinimalFDX() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FinalDraft DocumentType="Script">
        <Content>
        <Paragraph Type="Scene Heading" SceneNumber="12A"><Text>INT. HOFFMAN OFFICE — DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She opens the door.</Text></Paragraph>
        <Paragraph Type="Character"><Text>ALICE</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>Hello.</Text></Paragraph>
        </Content>
        </FinalDraft>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-test-\(UUID().uuidString).fdx")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try ScriptImporter.parse(fdxURL: url)
        XCTAssertEqual(result.scenes.count, 1)
        XCTAssertEqual(result.scenes.first?.sceneNumber, "12A")
        XCTAssertTrue(result.scenes.first?.slugline.contains("INT. HOFFMAN OFFICE") ?? false)
        XCTAssertEqual(result.scenes.first?.characters, ["ALICE"])
        XCTAssertTrue(result.scenes.first?.synopsis?.contains("door") ?? false)
    }

    func testMapClipsToScriptNarrativeMetaConfidence() {
        let script = ScriptImportResult(
            title: "T",
            scenes: [
                ScriptScene(
                    sceneNumber: "12A",
                    slugline: "INT. OFFICE — DAY",
                    pageNumber: 1,
                    characters: [],
                    synopsis: nil
                )
            ],
            totalPages: 1,
            sourceURL: URL(fileURLWithPath: "/tmp/x.fdx"),
            parsedAt: "2026-01-01T00:00:00Z"
        )
        let clip = Clip(
            projectId: "p",
            checksum: String(repeating: "a", count: 64),
            sourcePath: "/tmp/a.mov",
            sourceSize: 1,
            sourceFormat: .h264,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 1,
            narrativeMeta: .init(sceneNumber: "12A", shotCode: "A", takeNumber: 1, cameraId: "A"),
            documentaryMeta: nil,
            projectMode: .narrative
        )
        let mappings = ScriptImporter.mapClipsToScript(clips: [clip], script: script)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].confidence, 1.0, accuracy: 0.001)
        XCTAssertEqual(mappings[0].source, .narrativeMeta)
        XCTAssertEqual(mappings[0].sceneNumber, "12A")
    }

    func testMapClipsToScriptHandlesDuplicateSceneNumbersWithoutCrashing() {
        let duplicateA = ScriptScene(
            sceneNumber: "12A",
            slugline: "INT. OFFICE — DAY",
            pageNumber: 1,
            characters: [],
            synopsis: nil
        )
        let duplicateB = ScriptScene(
            sceneNumber: "12A",
            slugline: "INT. OFFICE — NIGHT",
            pageNumber: 2,
            characters: [],
            synopsis: nil
        )
        let script = ScriptImportResult(
            title: "T",
            scenes: [duplicateA, duplicateB],
            totalPages: 2,
            sourceURL: URL(fileURLWithPath: "/tmp/x.fdx"),
            parsedAt: "2026-01-01T00:00:00Z"
        )

        let clip = Clip(
            projectId: "p",
            checksum: String(repeating: "a", count: 64),
            sourcePath: "/tmp/a.mov",
            sourceSize: 1,
            sourceFormat: .h264,
            sourceFps: 24,
            sourceTimecodeStart: "01:00:00:00",
            duration: 1,
            narrativeMeta: .init(sceneNumber: "12A", shotCode: "A", takeNumber: 1, cameraId: "A"),
            documentaryMeta: nil,
            projectMode: .narrative
        )

        let mappings = ScriptImporter.mapClipsToScript(clips: [clip], script: script)
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0].sceneNumber, "12A")
        XCTAssertEqual(mappings[0].scriptScene?.slugline, duplicateA.slugline)
    }
}
