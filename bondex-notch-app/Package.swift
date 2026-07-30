// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BondexNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BondexNotch",
            path: "Sources/BondexNotch",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BondexNotchTests",
            dependencies: ["BondexNotch"],
            path: "Tests/BondexNotchTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
