// swift-tools-version: 6.0
import PackageDescription

// Pure logic for Murmur: no dependencies and no Apple-only frameworks, so the same package builds
// and tests on macOS and on Linux CI. Anything that touches AppKit, AVFoundation, CoreAudio or
// CoreGraphics belongs in the app package instead.
let package = Package(
    name: "MurmurCore",
    platforms: [
        .macOS("14.2"),
    ],
    products: [
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
    ],
    targets: [
        .target(name: "MurmurCore"),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
    ]
)
