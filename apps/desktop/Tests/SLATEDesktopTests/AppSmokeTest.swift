// SLATE — AppSmokeTest
// Owned by: Claude Code
//
// Fast smoke tests that verify:
//  1. GRDBClipStore opens and bootstraps the schema without crashing
//  2. ReviewStatus canonical cases all have non-empty display names
//  3. IngestStage canonical cases cover .checksum…complete and .error
//  4. ProjectStatistics.empty has the correct zero values
//  5. Annotation canonical fields compile (i.e. `userDisplayName`, `body`, `timecodeIn`)
//
// These tests run against an in-memory temp database — no network, no daemon.

import Testing
import Foundation
@testable import SLATECore
@testable import SLATESharedTypes
@testable import SLATEUI

// MARK: - ReviewStatus

@Suite("ReviewStatus canonical cases")
struct ReviewStatusTests {
    @Test("All canonical cases have non-empty displayName")
    func allCasesHaveDisplayName() {
        for status in ReviewStatus.allCases {
            #expect(!status.displayName.isEmpty, "ReviewStatus.\(status) has empty displayName")
        }
    }

    @Test("Canonical case values match contract")
    func canonicalRawValues() {
        #expect(ReviewStatus.unreviewed.rawValue  == "unreviewed")
        #expect(ReviewStatus.circled.rawValue     == "circled")
        #expect(ReviewStatus.flagged.rawValue     == "flagged")
        #expect(ReviewStatus.x.rawValue           == "x")
        #expect(ReviewStatus.deprioritized.rawValue == "deprioritized")
    }
}

// MARK: - IngestStage

@Suite("IngestStage canonical cases")
struct IngestStageTests {
    @Test("No .database case — it was removed in C2")
    func noDatabaseCase() {
        // The canonical enum has: checksum, copy, verify, proxy, sync, complete, error
        let expected: Set<String> = ["checksum", "copy", "verify", "proxy", "sync", "complete", "error"]
        let actual = Set(IngestStage.allCases.map(\.rawValue))
        #expect(actual == expected)
    }
}

// MARK: - ProjectStatistics

@Suite("ProjectStatistics defaults")
struct ProjectStatisticsTests {
    @Test(".empty has zero values")
    func emptyStatistics() {
        let stats = ProjectStatistics.empty
        #expect(stats.totalClips == 0)
        #expect(stats.reviewProgress == 0.0)
        #expect(stats.proxyProgress == 0.0)
    }
}

// MARK: - Annotation canonical fields

@Suite("Annotation canonical fields")
struct AnnotationFieldTests {
    @Test("Annotation init uses canonical parameter names")
    func canonicalInit() {
        let a = Annotation(
            userId: "u1",
            userDisplayName: "Alice",
            timecodeIn: "00:01:23:04",
            body: "Great take",
            type: .text
        )
        #expect(a.userDisplayName == "Alice")
        #expect(a.timecodeIn == "00:01:23:04")
        #expect(a.body == "Great take")
        #expect(a.type == .text)
    }
}

// MARK: - GRDBClipStore bootstrap

@Suite("GRDBClipStore bootstrap")
struct GRDBClipStoreBootstrapTests {
    @MainActor
    @Test("Opens in-memory temp DB without throwing")
    func opensWithoutCrash() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-smoke-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = GRDBClipStore(dbPath: tempPath)
        // Give the async init Task a moment to run
        try await Task.sleep(for: .milliseconds(200))

        // After setup the store should not be in loading state
        #expect(!store.loading)
        #expect(store.error == nil)
    }

    @MainActor
    @Test("Clips array is empty on a fresh database")
    func freshDatabaseHasNoClips() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-smoke-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = GRDBClipStore(dbPath: tempPath)
        try await Task.sleep(for: .milliseconds(200))

        #expect(store.clips.isEmpty)
        #expect(store.projects.isEmpty)
    }
}

// MARK: - CloudSync configuration

@Suite("Cloud sync destination validation")
struct CloudSyncDestinationValidationTests {
    @Test("Google Drive destinations require a folder ID")
    func googleDriveRequiresFolderId() throws {
        #expect(throws: CloudSyncStoreError.self) {
            _ = try CloudSyncDestinationConfiguration().validated(for: .googleDrive)
        }
    }

    @Test("Dropbox destinations require a remote path")
    func dropboxRequiresPath() throws {
        #expect(throws: CloudSyncStoreError.self) {
            _ = try CloudSyncDestinationConfiguration().validated(for: .dropbox)
        }
    }

    @Test("Frame.io destinations require account and folder IDs")
    func frameIORequiresAccountAndFolder() throws {
        #expect(throws: CloudSyncStoreError.self) {
            _ = try CloudSyncDestinationConfiguration(remoteFolderId: "folder-only").validated(for: .frameIO)
        }
    }

    @Test("Validation trims provider configuration")
    func validationTrimsWhitespace() throws {
        let config = try CloudSyncDestinationConfiguration(remotePath: "  /Apps/SLATE  ")
            .validated(for: .dropbox)
        #expect(config.remotePath == "/Apps/SLATE")
    }
}

// MARK: - CloudSync persistence

@Suite("Cloud sync store persistence")
struct CloudSyncStorePersistenceTests {
    @MainActor
    @Test("Saving a destination persists it for the project")
    func savingDestinationPersists() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("slate-cloud-sync-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let store = CloudSyncStore(dbPath: tempPath)
        let project = Project(name: "Sync Project", mode: .documentary)

        try await store.saveDestination(
            name: "Dropbox Review",
            provider: .dropbox,
            configuration: CloudSyncDestinationConfiguration(remotePath: "/Apps/SLATE/SyncProject"),
            project: project
        )

        await store.load(project: project)

        #expect(store.destinations.count == 1)
        #expect(store.destinations.first?.provider == .dropbox)
        #expect(store.destinations.first?.configuration.remotePath == "/Apps/SLATE/SyncProject")
    }
}
