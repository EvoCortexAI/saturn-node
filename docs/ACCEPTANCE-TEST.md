# Acceptance Test

## Deterministic gate

Contract fixtures, incremental fake streaming, single-terminal cancellation, identity/limit denials, typed saturation/timeouts, metadata-only logs, and fail-closed manifest compatibility must pass before hardware work.

The deterministic adapter gate also requires:

- contiguous event sequencing through normal completion;
- contiguous event sequencing through cancellation;
- a successful request after cancellation;
- already-expired requests rejected before mesh generation starts;
- mesh timeout failures mapped to `requestTimedOut`;
- sustained-runner orchestration exercised against the deterministic simulated mesh runtime;
- quiescence checked after every ordinary, cancellation, and recovery terminal.

## Real Apple-silicon gate

Primary model identity aligned with mesh `AcceptanceModelPin`:

- **Model ID:** `mlx-community/Qwen3-8B-4bit`
- **Pinned mesh revision:** `8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e`
- **Mesh doc:** `saturn-mlx-mesh` → `Docs/ACCEPTANCE-MODEL.md`
- **Mesh baseline:** `swift run SaturnMLXMeshSmoke`
- **Mesh cancel/recovery:** `swift run SaturnMLXMeshSmoke --cancel-recovery`
- **Node baseline:** `swift run saturn-node --real-smoke`
- **Node cancel/recovery:** `swift run saturn-node --real-smoke --cancel-recovery`
- **Node sustained:** `swift run saturn-node --real-smoke --requests 20 --cancellations 5`

Standard hardware evidence must keep prompt and generated-response bodies out of captured output. The smoke commands suppress generated content by default. Do not use `--show-content` when collecting acceptance artifacts.

The sustained command has exact semantics: load the model once in one process, run **20 ordinary completion requests**, then run **5 cancellation → quiescence → recovery cycles**. The five recovery requests are additive and are not included in the 20 ordinary requests.

`--cancel-recovery` remains a compatibility alias for one cancellation/recovery cycle when `--cancellations` is not supplied.

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
- metadata-only telemetry count / outcome;
- memory pressure and swap before and after the sustained run;
- first-request versus same-process timing explicitly, without presenting either as a public benchmark.

The runner labels request 1 as `first_after_model_load` and later ordinary requests as `same_process`. Host-level cold/warm cache state must be recorded separately by the operator; do not infer it from request timing alone.

## Sustained runner output

A passing sustained run reports per-request metadata plus aggregate timing summaries. Required pass counters include:

```text
ordinary_requests_passed=20/20
cancellations_passed=5/5
recoveries_passed=5/5
sequence_violations=0
quiescence_checks=pass
active_requests_remaining=0
result=pass
```

Aggregate timing uses minimum, median, and nearest-rank p95 for ordinary and recovery TTFD/generation duration. These are internal acceptance measurements, not public benchmark claims.

Any request failure, invalid event sequence, missed cancellation terminal, failed recovery, or non-quiescent runtime fails the command and exits non-zero.

## Gate criteria

- One pinned runtime and model load (`Qwen3-8B-4bit`).
- Baseline real mesh completion succeeds.
- Mesh explicit cancellation leaves no active request and a subsequent real request succeeds.
- Baseline real Node-adapter completion succeeds with contiguous Saturn event sequencing.
- Node-adapter explicit cancellation produces a contiguous cancelled terminal, leaves no active mesh request, and a subsequent real request succeeds.
- 20/20 sequential ordinary Node requests complete in one process and one model load under the fixed acceptance contract.
- 5/5 controlled Node cancellation/recovery cycles leave no orphan generation and each recovery request succeeds.
- The runtime is quiescent after every ordinary, cancellation, and recovery terminal.
- One fresh-process restart returns to successful inference.
- One managed Saturn-Node service restart returns to successful inference once a managed service lifecycle exists.
- Model/node identity and metadata-only usage are correct.
- Prompt and output bodies appear in zero standard logs or acceptance artifacts.

The one-shot baseline/cancel-recovery artifact proves the basic real-runtime path only. Do not describe the sustained hardware gate as closed until the required counts and fresh-process restart evidence are recorded.

## Controlled hardware procedure

For sustained evidence, use a controlled host state rather than shell-looping one-shot smoke commands:

1. Start from the accepted Saturn-Node and mesh SHAs with the real-runtime resource bundles intact.
2. Prefer a fresh host restart, then leave the graphical session logged out and allow the machine to settle.
3. Record host/toolchain/model provenance, power configuration, memory pressure, and swap state.
4. Run exactly one sustained command with one process/model load.
5. Record post-run memory pressure and swap state and inspect early versus late request latency for pathological degradation.
6. Exit the process completely, start a fresh process, load the model again, and require at least one successful completion.
7. Attach metadata-only evidence to the controlling Node and mesh trackers.

Do not use repeated shell invocations of `--real-smoke` as a substitute for sustained acceptance because each process reloads the runtime and does not test long-lived request sequencing.

## Deadline gate

Current adapter behavior rejects a request that is already expired before mesh generation begins and maps a runtime-emitted timeout to `requestTimedOut`.

The adapter does **not yet** enforce a hard wall-clock `deadlineAt` that expires while real generation is already in progress. That behavior must be implemented and accepted before production transport is enabled. Do not interpret sustained hardware acceptance as closing the in-flight deadline/runtime-contract gate.

## Scope boundary

**Not in the primary gate:** Qwen 32B-class models, multi-node placement, public benchmark claims, production listener exposure, production credentials, or deployment changes.

Default executable composition remains fail-closed (`UnavailableInferenceRuntime`). `--real-smoke` is an explicit hardware-test path only; it does not change production composition or authorize deployment.

These are internal engineering gates, not public benchmark claims.
