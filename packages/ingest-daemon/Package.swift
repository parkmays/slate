// swift-tools-version: 5.9
// SLATE — IngestDaemon Swift Package
// Owned by: Claude Code
// Depends on: SLATESharedTypes

import PackageDescription

let package = Package(
    name: "IngestDaemon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "IngestDaemon",
            targets: ["IngestDaemon"]
        ),
        .executable(
            name: "slate-ingest",
            targets: ["IngestDaemonCLI"]
        )
    ],
    dependencies: [
        // Shared types — local path reference
        .package(path: "../shared-types"),
        // Sync engine — for audio/video synchronization
        .package(path: "../sync-engine"),
        // AI pipeline — for media scoring
        .package(path: "../ai-pipeline"),
        // GRDB — local SQLite ORM (offline-first)
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "IngestDaemon",
            dependencies: [
                .product(name: "SLATESharedTypes", package: "shared-types"),
                .product(name: "SLATESyncEngine", package: "sync-engine"),
                .product(name: "SLATEAIPipeline", package: "ai-pipeline"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/IngestDaemon",
            exclude: [
                "DesktopBridge.swift",
                "WatchFolderDaemon.swift"
            ],
            resources: [
                .copy("../../Resources/LUTs")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .linkedFramework("PDFKit")
            ]
        ),
        .executableTarget(
            name: "IngestDaemonCLI",
            dependencies: ["IngestDaemon"],
            path: "Sources/IngestDaemonCLI"
        ),
        .testTarget(
            name: "IngestDaemonTests",
            dependencies: [
                "IngestDaemon",
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Tests/IngestDaemonTests"
        )
    ]
)
