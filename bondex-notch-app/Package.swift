// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BondexNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates. EdDSA-signed, so it works without an Apple
        // Developer ID, and asks before it ever checks.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "BondexNotch",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/BondexNotch",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Where Sparkle.framework is found at launch: inside the app
                // bundle, and beside the bare binary `swift build` produces,
                // which the preview tool and agent hooks can also run.
                .unsafeFlags([
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "@loader_path"
                ])
            ]
        ),
        .testTarget(
            name: "BondexNotchTests",
            dependencies: ["BondexNotch"],
            path: "Tests/BondexNotchTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
