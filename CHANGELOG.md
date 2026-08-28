# Changelog

All notable changes to Saturn-Node will be documented in this file.

Versioning follows semantic-style `0.x.y`. See `docs/VERSIONING.md`, `docs/RELEASING.md`, and `docs/MARKDOWN-SCHEMA.md`.

A changelog section is not a published tag.

## [Unreleased]

- Credential envelope ADR, production verifier, private transport, and composition seams remain open under issue #4.
- Switch mesh pin to `.upToNextMinor(from: "0.2.0")` after the mesh `0.2.0` tag exists.

## [0.1.0] - 2026-08-28

First published semantic release. First Apache-2.0 tagged release. Tag is created only after this section lands on `main` and founder approval records the exact SHA.

- Private service boundary and fail-closed executable (no listener).
- Workload-compute contract v1 fixtures, schema, and CI validator.
- Deterministic fake runtime, sequence validator, claim validation tests.
- Mesh adapter with simulation + explicit `--real-smoke` real MLX path.
- Sustained hardware acceptance runner (20/20 + 5/5 cancel/recovery + restart).
- In-flight `deadlineAt` enforcement during active generation.
- Mesh pin remains revision `8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e` until `saturn-mlx-mesh` `0.2.0` is tagged.
- Mesh `0.2.0` candidate SHA recorded: `9aab96a2e24817fbb1898f8c133ad44469986805` (saturn-mlx-mesh#15). Not a tag.
- Relicense first-party `main` materials under Apache License 2.0.

See `docs/releases/0.1.0.md`.
