// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SLATEAIPipeline",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SLATEAIPipeline",
            targets: ["SLATEAIPipeline"]
        )
    ],
    dependencies: [
        .package(path: "../shared-types"),
        .package(path: "../sync-engine")
    ],
    targets: [
        .target(
            name: "SLATEAIPipeline",
            dependencies: [
                .product(name: "SLATESharedTypes", package: "shared-types"),
                .product(name: "SLATESyncEngine", package: "sync-engine")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SLATEAIPipelineTests",
            dependencies: [
                "SLATEAIPipeline",
                .product(name: "SLATESharedTypes", package: "shared-types"),
                .product(name: "SLATESyncEngine", package: "sync-engine")
            ]
        )
    ]
)
