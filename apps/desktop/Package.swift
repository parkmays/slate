// swift-tools-version: 5.9
// SLATE — Desktop App Swift Package
// Owned by: Claude Code
// Depends on: SLATESharedTypes, IngestDaemon, SyncEngine, AIPipeline

import PackageDescription

let package = Package(
    name: "SLATEDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "slate-desktop",
            targets: ["SLATEDesktop"]
        )
    ],
    dependencies: [
        // Local packages
        .package(path: "../../packages/shared-types"),
        .package(path: "../../packages/ingest-daemon"),
        .package(path: "../../packages/export-writers"),

        // External dependencies
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        .package(url: "https://github.com/supabase-community/supabase-swift", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "SLATECore",
            dependencies: [
                .product(name: "SLATESharedTypes", package: "shared-types"),
                .product(name: "IngestDaemon", package: "ingest-daemon"),
                .product(name: "ExportWriters", package: "export-writers"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/SLATECore",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "SLATEUI",
            dependencies: [
                "SLATECore",
                .product(name: "ExportWriters", package: "export-writers"),
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Sources/SLATEUI",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "SLATEDesktop",
            dependencies: [
                "SLATECore",
                "SLATEUI",
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Sources/SLATEDesktop"
        ),
        .testTarget(
            name: "SLATEDesktopTests",
            dependencies: [
                "SLATEDesktop",
                "SLATECore",
                "SLATEUI",
                .product(name: "ExportWriters", package: "export-writers"),
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Tests/SLATEDesktopTests"
        )
    ]
)
