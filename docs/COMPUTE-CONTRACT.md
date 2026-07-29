# Workload Compute Contract

**Status:** Provisional boundary; wire format not yet frozen  
**Canonical review gate:** `EvoCortexAI/saturn-control#3`

The caller is a managed agent container assigned by Saturn-Control. Frontend credentials are invalid.

The reviewed contract must define capability/model discovery, workload credential presentation, streamed frames and one terminal completion, request/workload/deployment/model/node correlation, all resource limits, connect/idle/total timeouts, cancellation and disconnect, saturation/retry semantics, metadata-only usage, and stable typed failures.

Prompts and generated content are inference payloads but are excluded from normal audit logs. Unknown versions and fields fail closed. Cancellation closes the stream once. The bootstrap Swift types are not a frozen HTTP or credential wire format.
