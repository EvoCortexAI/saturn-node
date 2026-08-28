# Versioning

**Type:** versioning-policy
**Status:** binding; Node `0.1.0` and mesh `0.2.0` tags exist
**Authority:** compatibility contract only; this file does not retarget a tag
**Schema:** docs/MARKDOWN-SCHEMA.md

Architecture views: [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Principle

Saturn-Node uses semantic versions as the published package and evidence identity.

A released version identifies an immutable Git tag, and that tag resolves to one exact commit SHA. Downstream consumers that treat Node as a Swift package declare a bounded semantic version requirement and commit `Package.resolved`. Raw commit SHAs remain provenance and CI-verification data.

```text
semantic version = compatibility contract
Git tag          = immutable release identity
commit SHA       = source provenance
Package.resolved = exact consumer resolution
```

Do not use a floating branch as a package dependency. Do not retarget a released version tag.

The operational release procedure is defined in `RELEASING.md`.

## Current release line

The first published semantic release is `0.1.0` on SHA `ba5f7c61d87a2e111d9e1b70d78bb74b964a2454`. It is the first Apache-2.0 tagged release. The active pre-1.0 compatibility line is `0.1.x`.

`0.1.0` is a fail-closed service-boundary package. It is **not** an operational listener, production verifier, or SN01 deploy.

## Mesh dependency

Saturn-Node consumes `saturn-mlx-mesh` `0.2.x`.

- Published mesh tag: `0.2.0` → `9aab96a2e24817fbb1898f8c133ad44469986805`.
- Hardware evidence SHA `8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e` remains provenance. It is no longer the Node manifest pin.
- Normal contract:

```swift
.package(
    url: "https://github.com/EvoCortexAI/saturn-mlx-mesh.git",
    .upToNextMinor(from: "0.2.0")
)
```

Commit `Package.resolved` when the file is part of the checkout used for release evidence. CI must verify origin, resolved version, and exact resolved SHA.

A floating `branch: "main"` mesh dependency is not an approved release contract. Direct revision pins are recovery-only.

## Before the first stable release

Use `0.x.y` while the private service contract is stabilizing.

- `0.x.0` may introduce deliberate contract/API changes.
- `0.x.y` patch releases contain compatible fixes within the current minor line.
- Direct revision dependencies are reserved for approved temporary recovery and must not remain the normal contract.

Each new pre-1.0 tag is created only after release scope is approved and all gates in `RELEASING.md` pass.

## After `1.0.0`

Requires the secure single-node MVP acceptance in issue #4: authenticated private request, pinned model, stream, cancel/complete, metadata evidence, cleanup, subsequent request. A tag does not by itself make Node operational.

## Release provenance

```text
version -> immutable tag -> exact commit SHA
```
