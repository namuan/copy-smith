// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopySmith",
    platforms: [
        .macOS("13.0")
    ],
    dependencies: [
        .package(url: "https://github.com/eastriverlee/LLM.swift/", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "CopySmith",
            dependencies: [
                .product(name: "LLM", package: "LLM.swift")
            ],
            path: "Sources/CopySmith"
        ),
        .testTarget(
            name: "CopySmithTests",
            dependencies: ["CopySmith"],
            path: "Tests/CopySmithTests"
        )
    ]
)
