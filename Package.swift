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
        // Mesh: Swift 6.3 / platform 26 baseline, real MeshModelInferenceRuntime,
        // hardware acceptance smoke, and deterministic simulation for CI.
        .package(
            url: "https://github.com/EvoCortexAI/saturn-mlx-mesh.git",
            revision: "8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e"
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
