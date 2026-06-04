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
        .executableTarget(
            name: "Embeddings",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "GenerateImage",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "TranscribeAudio",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "GenerateSpeech",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "GenerateAudio",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "TransformAudio",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "Dubbing",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "GenerateVideo",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "Rerank",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "Telemetry",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
        .executableTarget(
            name: "ErrorHandling",
            dependencies: [
                .product(name: "SwiftAISDK", package: "SwiftAISDK"),
            ]
        ),
    ]
)
