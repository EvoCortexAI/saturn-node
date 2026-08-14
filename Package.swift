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
        // Real MLXInferenceRuntime (MeshModelInferenceRuntime) + AcceptanceModelPin.
        // Pin tip of agent/real-mesh-model-inference-runtime until that PR merges to main;
        // then bump to the merge commit SHA.
        .package(
            url: "https://github.com/EvoCortexAI/saturn-mlx-mesh.git",
            revision: "c91f5965f5d4640a48d9b9f1834550fae61b1a3a"
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
