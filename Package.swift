// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "SaturnNode",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SaturnNodeCore", targets: ["SaturnNodeCore"]),
        .executable(name: "saturn-node", targets: ["saturn-node"])
    ],
    dependencies: [
        // SUA §9: single canonical authority contract. Node is verifier only — never issuer.
        .package(
            url: "https://github.com/EvoCortexAI/evo-ethics-framework.git",
            branch: "main"
        ),
        // Narrow simulation-backed adapter surface only.
        // Pinned to mesh main after ConformanceIsolation fix (nonisolated generate).
        // Real-hardware MeshModel path and G3 reclamation remain blocked on mesh#1.
        .package(
            url: "https://github.com/EvoCortexAI/saturn-mlx-mesh.git",
            revision: "779dd871ab386ed50b47e2e2c994a16ae2d8d1db"
        )
    ],
    targets: [
        .target(
            name: "SaturnNodeCore",
            dependencies: [
                .product(name: "SaturnAuthority", package: "evo-ethics-framework"),
                .product(name: "SaturnMLXMesh", package: "saturn-mlx-mesh")
            ]
        ),
        .executableTarget(
            name: "saturn-node",
            dependencies: ["SaturnNodeCore"]
        ),
        .testTarget(
            name: "SaturnNodeCoreTests",
            dependencies: [
                "SaturnNodeCore",
                .product(name: "SaturnAuthority", package: "evo-ethics-framework"),
                .product(name: "SaturnMLXMesh", package: "saturn-mlx-mesh")
            ]
        )
    ]
)
