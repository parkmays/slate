// swift-tools-version: 5.9
// SLATE — SLATESharedTypes Swift Package
// Owned by: Claude Code
// Consumed by: all other Swift packages and the desktop app

import PackageDescription

let package = Package(
    name: "SLATESharedTypes",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SLATESharedTypes",
            targets: ["SLATESharedTypes"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SLATESharedTypes",
            dependencies: [],
            path: "Sources/SLATESharedTypes",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SLATESharedTypesTests",
            dependencies: ["SLATESharedTypes"],
            path: "Tests/SLATESharedTypesTests"
        )
    ]
)
