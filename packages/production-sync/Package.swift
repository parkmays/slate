// swift-tools-version: 5.9
// SLATE — Production Sync (Airtable / ShotGrid). Distinct from SLATESyncEngine (audio/multicam).

import PackageDescription

let package = Package(
    name: "SLATEProductionSync",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SLATEProductionSync", targets: ["SLATEProductionSync"])
    ],
    dependencies: [
        .package(path: "../shared-types")
    ],
    targets: [
        .target(
            name: "SLATEProductionSync",
            dependencies: [
                .product(name: "SLATESharedTypes", package: "shared-types")
            ],
            path: "Sources/SLATEProductionSync"
        ),
        .testTarget(
            name: "SLATEProductionSyncTests",
            dependencies: ["SLATEProductionSync"],
            path: "Tests/SLATEProductionSyncTests"
        )
    ]
)
