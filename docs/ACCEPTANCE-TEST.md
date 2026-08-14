# Acceptance Test

## Deterministic gate

Contract fixtures, incremental fake streaming, single-terminal cancellation, identity/limit denials, typed saturation/timeouts, metadata-only logs, and fail-closed manifest compatibility must pass before hardware work.

The deterministic adapter gate also requires:

- contiguous event sequencing through normal completion;
- contiguous event sequencing through cancellation;
- a successful request after cancellation;
- already-expired requests rejected before mesh generation starts;
- mesh timeout failures mapped to `requestTimedOut`.

## Real Apple-silicon gate

Primary model identity aligned with mesh `AcceptanceModelPin`:

- **Model ID:** `mlx-community/Qwen3-8B-4bit`
- **Pinned mesh revision:** `8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e`
- **Mesh doc:** `saturn-mlx-mesh` → `Docs/ACCEPTANCE-MODEL.md`
- **Mesh baseline:** `swift run SaturnMLXMeshSmoke`
- **Mesh cancel/recovery:** `swift run SaturnMLXMeshSmoke --cancel-recovery`
- **Node baseline:** `swift run saturn-node --real-smoke`
- **Node cancel/recovery:** `swift run saturn-node --real-smoke --cancel-recovery`

Standard hardware evidence must keep prompt and generated-response bodies out of captured output. The smoke commands suppress generated content by default. Do not use `--show-content` when collecting acceptance artifacts.

## Evidence to record

Before the real commands, capture metadata only:

```sh
git rev-parse HEAD
swift --version
xcodebuild -version
sw_vers
uname -m
swift package show-dependencies --format json
```

Record:

- host class and memory;
- OS build;
- Saturn-Node commit SHA;
- pinned `saturn-mlx-mesh` revision;
- resolved MLX / Hugging Face / transformers dependency revisions;
- model ID and actual weight revision loaded;
- load duration;
- time to first non-empty delta;
- generated delta/token count and generation duration;
- completion / cancellation outcome;
- metadata-only telemetry count / outcome.

## Gate criteria

- One pinned runtime and model load (`Qwen3-8B-4bit`).
- Baseline real mesh completion succeeds.
- Mesh explicit cancellation leaves no active request and a subsequent real request succeeds.
- Baseline real Node-adapter completion succeeds with contiguous Saturn event sequencing.
- Node-adapter explicit cancellation produces a contiguous cancelled terminal, leaves no active mesh request, and a subsequent real request succeeds.
- 20/20 sequential Node requests complete under the fixed acceptance contract.
- 5/5 controlled Node cancellations leave no orphan generation.
- One fresh-process restart returns to successful inference.
- One managed Saturn-Node service restart returns to successful inference once a managed service lifecycle exists.
- Model/node identity and metadata-only usage are correct.
- Prompt and output bodies appear in zero standard logs or acceptance artifacts.

## Deadline gate

Current adapter behavior rejects a request that is already expired before mesh generation begins and maps a runtime-emitted timeout to `requestTimedOut`.

The adapter does **not yet** enforce a hard wall-clock `deadlineAt` that expires while real generation is already in progress. That behavior must be implemented and accepted before production transport is enabled. Do not interpret the current hardware smoke as closing the in-flight deadline gate.

## Scope boundary

**Not in the primary gate:** Qwen 32B-class models, multi-node placement, public benchmark claims, production listener exposure, production credentials, or deployment changes.

Default executable composition remains fail-closed (`UnavailableInferenceRuntime`). `--real-smoke` is an explicit hardware-test path only; it does not change production composition or authorize deployment.

These are internal engineering gates, not public benchmark claims.
