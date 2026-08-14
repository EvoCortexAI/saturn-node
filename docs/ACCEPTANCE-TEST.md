# Acceptance Test

## Deterministic gate

Contract fixtures, incremental fake streaming, single terminal cancellation, identity/limit denials, typed saturation/timeouts, metadata-only logs, and fail-closed manifest compatibility must pass before hardware work.

## Real Apple-silicon gate

Primary model identity (aligned with mesh `AcceptanceModelPin`):

- **Model ID:** `mlx-community/Qwen3-8B-4bit`
- **Mesh doc:** `saturn-mlx-mesh` → `Docs/ACCEPTANCE-MODEL.md`
- **Smoke:** `swift run SaturnMLXMeshSmoke` on target hardware

Gate criteria:

- One pinned runtime and model load (`Qwen3-8B-4bit`).
- 20/20 sequential requests complete.
- 5/5 controlled cancellations leave no orphan generation.
- One managed restart returns to successful inference.
- Model/node identity and metadata-only usage are correct.
- Prompt and output bodies appear in zero standard logs.

**Not in primary gate before KF:** Qwen 32B-class models (optional second-slide only).

Default executable composition remains fail-closed (`UnavailableInferenceRuntime`). Opt-in real mesh runtime is Founder-gated after mesh#1 evidence is recorded.

These are internal engineering gates, not public benchmark claims.
