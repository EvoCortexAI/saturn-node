# Changelog

All notable changes to Saturn-Node will be documented in this file.

Versioning follows semantic-style `0.x.y`. See `docs/VERSIONING.md`, `docs/RELEASING.md`, and `docs/MARKDOWN-SCHEMA.md`.

A changelog section is not a published tag.

## [Unreleased]

- Consume `saturn-mlx-mesh` `0.2.0` via `.upToNextMinor(from: "0.2.0")`. Tagged mesh SHA is `9aab96a2e24817fbb1898f8c133ad44469986805`. Does not retarget Node `0.1.0`.
- Extract `MeshRuntimeMapping` and pin mesh→Saturn error, state, and deadline-admission tables in Swift Testing.
- Slim `MeshInferenceRuntimeAdapter` onto that mapping; optional injected clock for admission.
- Compress README / architecture / schema so published mesh `0.2.0` is the documented pin, not the retired revision pin.
- Add Linux policy lane for v1 compute-contract validation. Swift/MLX build and deploy remain Apple Silicon only.
- Credential envelope ADR, production verifier, private transport, and composition seams remain open under issue #4.

## [0.1.0] - 2026-08-28

First published semantic release. First Apache-2.0 tagged release. Tag SHA `ba5f7c61d87a2e111d9e1b70d78bb74b964a2454`.

- Private service boundary and fail-closed executable (no listener).
- Workload-compute contract v1 fixtures, schema, and CI validator.
- Deterministic fake runtime, sequence validator, claim validation tests.
- Mesh adapter with simulation + explicit `--real-smoke` real MLX path.
- Sustained hardware acceptance runner (20/20 + 5/5 cancel/recovery + restart).
- In-flight `deadlineAt` enforcement during active generation.
- Mesh pin at tag time: revision `8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e`.
- Relicense first-party `main` materials under Apache License 2.0.

See `docs/releases/0.1.0.md`.
