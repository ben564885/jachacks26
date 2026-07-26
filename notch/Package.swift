// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SynqitNotch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SynqitNotch", targets: ["SynqitNotch"])
    ],
    dependencies: [
        // Pinned exactly: this library has flagged breaking changes between releases.
        // The API verified against 1.1.0 is expand(on:)/compact(on:)/hide(), all async + @MainActor.
        .package(url: "https://github.com/MrKai77/DynamicNotchKit.git", exact: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "SynqitNotch",
            dependencies: ["DynamicNotchKit"],
            path: "Sources/SynqitNotch"
        ),
        .testTarget(
            name: "SynqitNotchTests",
            dependencies: ["SynqitNotch"],
            path: "Tests/SynqitNotchTests"
        )
    ]
)
