// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SaturnNode",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SaturnNodeCore", targets: ["SaturnNodeCore"]),
        .executable(name: "saturn-node", targets: ["saturn-node"])
    ],
    targets: [
        .target(name: "SaturnNodeCore"),
        .executableTarget(name: "saturn-node", dependencies: ["SaturnNodeCore"]),
        .testTarget(name: "SaturnNodeCoreTests", dependencies: ["SaturnNodeCore"])
    ]
)
