// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrokIP",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GrokIP", targets: ["GrokIP"]),
        .library(name: "GrokIPCore", targets: ["GrokIPCore"])
    ],
    targets: [
        .target(
            name: "GrokIPCore",
            path: "Sources/GrokIPCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "GrokIP",
            dependencies: ["GrokIPCore"],
            path: "Sources/GrokIP",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GrokIPTests",
            dependencies: ["GrokIPCore"],
            path: "Tests/GrokIPTests"
        )
    ]
)
