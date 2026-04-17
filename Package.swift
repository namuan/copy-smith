// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopySmith",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "CopySmith",
            path: "Sources/CopySmith"
        ),
        .testTarget(
            name: "CopySmithTests",
            dependencies: ["CopySmith"],
            path: "Tests/CopySmithTests"
        )
    ]
)
