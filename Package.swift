// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FIXLens",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "FIXLens",
            path: "Sources/FIXLens",
            resources: [
                .copy("Resources/FIX44.xml"),
                .copy("Resources/logo-color.png"),
                .copy("Resources/logo-white.png"),
                .process("Resources/Assets.xcassets")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
