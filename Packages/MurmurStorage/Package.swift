// swift-tools-version: 6.0
import PackageDescription

// Murmur's on-disk history: a GRDB-backed SQLite database in Application Support. Kept apart from
// MurmurCore so the core stays dependency-free and Linux-testable; these tests run on macOS CI.
let package = Package(
    name: "MurmurStorage",
    platforms: [
        .macOS("14.2"),
    ],
    products: [
        .library(name: "MurmurStorage", targets: ["MurmurStorage"]),
    ],
    dependencies: [
        .package(path: "../MurmurCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "MurmurStorage",
            dependencies: [
                .product(name: "MurmurCore", package: "MurmurCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "MurmurStorageTests", dependencies: ["MurmurStorage"]),
    ]
)
