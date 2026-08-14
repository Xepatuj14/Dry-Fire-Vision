// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DryFireVision",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DryFireVisionCore",
            targets: ["DryFireVisionCore"]
        )
    ],
    targets: [
        .target(
            name: "DryFireVisionCore",
            path: "DryFireVision",
            exclude: [
                "App/DryFireVisionApp.swift",
                "Domain/Baselines/.gitkeep",
                "Domain/Comparison/.gitkeep",
                "Domain/Confidence/.gitkeep",
                "Domain/Metrics/.gitkeep",
                "Domain/Pose/.gitkeep",
                "Domain/Segmentation/.gitkeep",
                "Features/Calibration/.gitkeep",
                "Features/GhostMode/.gitkeep",
                "Features/LiveFireBeta/.gitkeep",
                "Features/Recording/.gitkeep",
                "Features/RepReview/.gitkeep",
                "Features/Results/.gitkeep",
                "Persistence/AssetStores/.gitkeep",
                "Persistence/Migrations/.gitkeep",
                "Persistence/Models/.gitkeep",
                "Services/AudioEventDetection/.gitkeep",
                "Services/Camera/.gitkeep",
                "Services/Media/.gitkeep",
                "Services/PoseDetection/.gitkeep",
                "Shared/Logging/.gitkeep",
                "Shared/Utilities/.gitkeep"
            ]
        ),
        .target(
            name: "DryFireVisionTestFixtures",
            dependencies: ["DryFireVisionCore"],
            path: "Tests/Fixtures",
            exclude: [".gitkeep"]
        ),
        .testTarget(
            name: "DryFireVisionDomainTests",
            dependencies: [
                "DryFireVisionCore",
                "DryFireVisionTestFixtures"
            ],
            path: "Tests/Domain"
        ),
        .testTarget(
            name: "DryFireVisionIntegrationTests",
            dependencies: [
                "DryFireVisionCore",
                "DryFireVisionTestFixtures"
            ],
            path: "Tests/Integration",
            exclude: [".gitkeep"]
        )
    ]
)
