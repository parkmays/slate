// swift-tools-version: 5.9
// SLATE monorepo — all Swift package sources live under packages/

import PackageDescription

let package = Package(
    name: "SLATEEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SLATESharedTypes",
            targets: ["SLATESharedTypes"]
        ),
        .library(
            name: "SLATESyncEngine",
            targets: ["SLATESyncEngine"]
        ),
        .library(
            name: "SLATEAIPipeline",
            targets: ["SLATEAIPipeline"]
        ),
        .library(
            name: "ExportWriters",
            targets: ["ExportWriters"]
        ),
        .library(
            name: "IngestDaemon",
            targets: ["IngestDaemon"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "SLATESharedTypes",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "packages/shared-types/Sources/SLATESharedTypes",
            resources: [
                .copy("Resources")
            ]
        ),
        .target(
            name: "SLATESyncEngine",
            dependencies: [
                "SLATESharedTypes"
            ],
            path: "packages/sync-engine/Sources/SLATESyncEngine",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("Vision")
            ]
        ),
        .target(
            name: "SLATEAIPipeline",
            dependencies: [
                "SLATESharedTypes",
                "SLATESyncEngine",
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "packages/ai-pipeline/Sources/SLATEAIPipeline",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreML"),
                .linkedFramework("Vision"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalPerformanceShaders"),
                .linkedFramework("Accelerate"),
                .linkedFramework("NaturalLanguage")
            ]
        ),
        .target(
            name: "ExportWriters",
            dependencies: [
                "SLATESharedTypes"
            ],
            path: "packages/export-writers/Sources/ExportWriters",
            resources: [
                .copy("Resources")
            ]
        ),
        .target(
            name: "IngestDaemon",
            dependencies: [
                "SLATESharedTypes",
                "SLATESyncEngine",
                "SLATEAIPipeline",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "packages/ingest-daemon/Sources/IngestDaemon",
            exclude: [
                "DesktopBridge.swift",
                "WatchFolderDaemon.swift"
            ],
            resources: [
                .copy("../../Resources/LUTs")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("PDFKit")
            ]
        ),
        .testTarget(
            name: "SLATESharedTypesTests",
            dependencies: [
                "SLATESharedTypes"
            ],
            path: "packages/shared-types/Tests/SLATESharedTypesTests"
        ),
        .testTarget(
            name: "SLATESyncEngineTests",
            dependencies: [
                "SLATESyncEngine"
            ],
            path: "packages/sync-engine/Tests/SLATESyncEngineTests"
        ),
        .testTarget(
            name: "SLATEAIPipelineTests",
            dependencies: [
                "SLATEAIPipeline"
            ],
            path: "packages/ai-pipeline/Tests/SLATEAIPipelineTests"
        ),
        .testTarget(
            name: "ExportWritersTests",
            dependencies: [
                "ExportWriters"
            ],
            path: "packages/export-writers/Tests/ExportWritersTests"
        ),
    ]
)
