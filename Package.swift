// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ai-sdk-port",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ai-sdk-port",
            targets: ["ai-sdk-port"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ai-sdk-port"
        ),
        .testTarget(
            name: "ai-sdk-portTests",
            dependencies: ["ai-sdk-port"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
