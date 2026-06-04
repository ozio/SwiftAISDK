// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SwiftAISDKExamples",
    platforms: [
        .macOS(.v12),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "GenerateText",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "StreamText",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "StructuredOutput",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "Tools",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
    ]
)
