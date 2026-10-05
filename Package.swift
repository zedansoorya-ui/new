// swift-tools-version: 6.0
import PackageDescription

// Murmur's app package. Pure logic lives in Packages/MurmurCore (no dependencies, also tested on
// Linux); speech engines in MurmurEngines; the menu-bar app and the eval CLI on top.
//
// Build the app bundle with scripts/build-app.sh (or `make app`), not `swift run`: macOS grants
// permissions to signed app bundles, not to a bare executable started from a terminal.
let package = Package(
    name: "Murmur",
    platforms: [
        .macOS("14.2"),
    ],
    products: [
        .executable(name: "Murmur", targets: ["MurmurApp"]),
        .executable(name: "murmur-eval", targets: ["MurmurEval"]),
    ],
    dependencies: [
        .package(path: "Packages/MurmurCore"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"),
    ],
    targets: [
        .target(
            name: "MurmurEngines",
            dependencies: [
                .product(name: "MurmurCore", package: "MurmurCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/MurmurEngines"
        ),
        .executableTarget(
            name: "MurmurApp",
            dependencies: [
                "MurmurEngines",
                .product(name: "MurmurCore", package: "MurmurCore"),
            ],
            path: "Sources/MurmurApp"
        ),
        .executableTarget(
            name: "MurmurEval",
            dependencies: [
                "MurmurEngines",
                .product(name: "MurmurCore", package: "MurmurCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/murmur-eval"
        ),
    ]
)
