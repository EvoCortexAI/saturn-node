# Acceptance Test

## Deterministic gate

Contract fixtures, incremental fake streaming, single terminal cancellation, identity/limit denials, typed saturation/timeouts, metadata-only logs, and fail-closed manifest compatibility must pass before hardware work.

## Real Apple-silicon gate

- One pinned runtime and model load.
- 20/20 sequential requests complete.
- 5/5 controlled cancellations leave no orphan generation.
- One managed restart returns to successful inference.
- Model/node identity and metadata-only usage are correct.
- Prompt and output bodies appear in zero standard logs.

These are internal engineering gates, not public benchmark claims.
