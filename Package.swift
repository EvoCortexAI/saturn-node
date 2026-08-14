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
        // Mesh: real MeshModelInferenceRuntime + AcceptanceModelPin + sim for CI.
        // Pin mesh main after PR #11 merge.
        .package(
            url: "https://github.com/EvoCortexAI/saturn-mlx-mesh.git",
            revision: "0d1e382b9b41c280bb7809133e380111804d0f2b"
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
