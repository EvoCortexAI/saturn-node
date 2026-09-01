# Releasing Saturn-Node

**Type:** release-procedure
**Status:** binding; `0.1.0` published; `0.1.x` cueing after green main CI
**Authority:** procedure only; cueing does not authorize SN01
**Schema:** docs/MARKDOWN-SCHEMA.md

Architecture views: [`ARCHITECTURE.md`](ARCHITECTURE.md).

Saturn-Node is released as a versioned Swift package. A release is a compatibility and provenance boundary, not an operational deploy.

There are two publication paths:

1. **Development cueing** -- automatic immutable `0.1.x` tags after green `main` CI.
2. **Formal release** -- founder-approved `0.2.0+` or `1.0.0`.

No release tag authorizes a listener, production credentials, launchd, or SN01 install.

## Development cueing (`0.1.x`)

| Rule | Value |
|---|---|
| Line | `0.1.x` |
| Trigger | Push to `main` whose Saturn-Node CI succeeded on that SHA |
| Allocator | `.github/workflows/tag-0.1-dev.yml` |
| First automatic tag | `0.1.1` |
| Increment | patch only; never skip or reuse |
| Tag target | exact CI-green `main` SHA |
| Retarget | forbidden |
| Notes file | not required |
| Founder approval | not required |
| Consumer declaration | `.upToNextMinor(from: "0.1.0")` plus committed `Package.resolved` |

Skip conditions: CI failed or cancelled; event was not a `main` push; SHA already has a `0.1.x` tag.

Cueing tags may include source-breaking changes. They do not authorize SN01.

## Formal release authority

Every `0.2.0+` or `1.0.0` release requires explicit approval of the intended version and release commit. Tags are immutable after publication and must never be retargeted.

Version semantics are defined in `VERSIONING.md`.

## License and publication

- `LICENSE` must contain the unmodified official Apache License 2.0 text.
- `NOTICE` records first-party copyright and trademark carve-outs.
- The first published semantic release is `0.1.0` and is the first Apache-2.0 release.
- `0.1.1` and later cueing tags are Apache-2.0. GitHub repository visibility remains a separate publication decision.

## Preconditions for a formal minor or major

Before publishing any `0.2.0+` or `1.0.0` release:

- `main` is the intended source and package CI is green on the exact release commit;
- `swift package dump-package` succeeds;
- contract validator and `swift test --parallel` succeed;
- fail-closed executable smoke succeeds (`swift run saturn-node`);
- `CHANGELOG.md` contains a dated section for the intended version;
- `docs/releases/<version>.md` records what the version is and is not;
- mesh dependency is the published `0.2.x` line;
- no known release-blocking correctness or security defect remains open;
- the release version and exact release commit have explicit founder approval.

## Formal release procedure

1. Choose the version according to `VERSIONING.md` (`0.2.0+` or `1.0.0`, never a `0.1.x` cue).
2. Update `CHANGELOG.md` and `docs/releases/<version>.md`.
3. Merge the release-preparation PR to `main` without creating a formal tag as a side effect. The automatic cueing workflow may still allocate the next `0.1.x` tag on that merge; that does not replace the formal version.
4. Record the resulting exact `main` commit SHA as the release candidate.
5. Verify CI on that exact commit.
6. Obtain explicit approval for the version and exact candidate SHA.
7. Create an immutable Git tag matching the semantic version. Do not prefix with `v`.
8. Create the GitHub release. Notes must record the exact commit SHA.
9. Verify the published tag resolves to that SHA.

## Consumer contract

```swift
.package(
    url: "https://github.com/EvoCortexAI/saturn-node.git",
    .upToNextMinor(from: "0.1.0")
)
```

A floating `branch: "main"` is never an approved dependency.

## Rollback

Never retarget a published tag. The next green `main` merge publishes the correction as the next `0.1.x` cue.
