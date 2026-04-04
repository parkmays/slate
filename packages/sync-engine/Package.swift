// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SLATESyncEngine",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SLATESyncEngine",
            targets: ["SLATESyncEngine"]
        )
    ],
    dependencies: [
        .package(path: "../shared-types")
    ],
    targets: [
        .target(
            name: "SLATESyncEngine",
            dependencies: [
                .product(name: "SLATESharedTypes", package: "shared-types")
            ]
        ),
        .testTarget(
            name: "SLATESyncEngineTests",
            dependencies: [
                "SLATESyncEngine",
                .product(name: "SLATESharedTypes", package: "shared-types")
            ]
        )
    ]
)
