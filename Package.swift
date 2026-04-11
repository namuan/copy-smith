// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopySmithMac",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "CopySmithMac",
            path: "Sources/CopySmithMac"
        ),
        .testTarget(
            name: "CopySmithMacTests",
            dependencies: ["CopySmithMac"],
            path: "Tests/CopySmithMacTests"
        )
    ]
)
