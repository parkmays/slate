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
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "packages/ai-pipeline/Sources/SLATEAIPipeline",
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
            path: "packages/export-writers/Sources/ExportWriters"
        ),
        .target(
            name: "IngestDaemon",
            dependencies: [
                "SLATESharedTypes",
                "SLATESyncEngine",
                "SLATEAIPipeline"
            ],
            path: "packages/ingest-daemon/Sources/IngestDaemon",
            linkerSettings: [
                .linkedFramework("AVFoundation")
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
            path: "packages/sync-engine/Tests/SLATESyncEngineTests",
            resources: [
                .copy("Fixtures")
            ]
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
        .testTarget(
            name: "SLATEIntegrationTests",
            dependencies: [
                "SLATESyncEngine",
                "SLATEAIPipeline",
                "SLATESharedTypes"
            ],
            path: "tests/IntegrationTests"
        ),
    ]
)
