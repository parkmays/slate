// swift-tools-version: 5.9
// SLATE — ExportWriters Swift Package
// Owned by: Claude Code
// Produces: FCPXML 1.11, CMX 3600 EDL, AAF, Premiere Pro XML, DaVinci Resolve XML

import PackageDescription

let package = Package(
    name: "ExportWriters",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ExportWriters",
            targets: ["ExportWriters"]
        )
    ],
    dependencies: [
        .package(path: "../shared-types")
    ],
    targets: [
        .target(
            name: "ExportWriters",
            dependencies: [
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Sources/ExportWriters",
            resources: [
                .copy("Resources/aaf_bridge.py"),
                .copy("Resources/python"),
                .copy("Resources/LICENSE-pyaaf2")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ExportWritersTests",
            dependencies: [
                "ExportWriters",
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Tests/ExportWritersTests"
        )
    ]
)
