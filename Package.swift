// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "network-mon",
    platforms: [.macOS(.v13)],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "network-mon"
        ),
        .testTarget(
            name: "network-monTests",
            dependencies: ["network-mon"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
