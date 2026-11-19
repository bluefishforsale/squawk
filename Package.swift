// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Squawk",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.3"),
    ],
    targets: [
        .target(name: "SquawkCore"),
        .executableTarget(
            name: "Squawk",
            dependencies: [
                "SquawkCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SquawkCoreTests", dependencies: ["SquawkCore"]),
    ]
)
