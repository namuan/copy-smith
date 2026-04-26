// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopySmith",
    platforms: [
        .macOS("14.0")
    ],
    dependencies: [
        .package(path: "vendor/LocalLLMClient")
    ],
    targets: [
        .executableTarget(
            name: "CopySmith",
            dependencies: [
                .product(name: "LocalLLMClient", package: "LocalLLMClient"),
                .product(name: "LocalLLMClientLlama", package: "LocalLLMClient"),
            ],
            path: "Sources/CopySmith",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .testTarget(
            name: "CopySmithTests",
            dependencies: ["CopySmith"],
            path: "Tests/CopySmithTests",
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        )
    ]
)
