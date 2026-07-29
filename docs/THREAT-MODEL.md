# Threat Model

Protected assets include workload credentials, verification keys, model artifacts, prompts/output, model capacity, usage evidence, node configuration, and revocation state.

| Threat | Mitigation direction |
|---|---|
| Frontend bypass | Reject frontend credentials and public exposure |
| Cross-deployment lease use | Bind workload and deployment IDs |
| Replay | Unique ID, expiry, revocation/epoch, replay state |
| Wrong node/model | Audience, node, and model binding |
| Resource exhaustion | Bounded queues and all request limits |
| Orphan stream | Structured cancellation tests |
| Content leakage | Metadata-only logging and redaction tests |
| Runtime drift | Pinned manifests and fail-closed compatibility |
| Workload authority expansion | No general tools or container control |
| Contract downgrade | Version rejection and signed policy/config direction |

Security review is required before choosing the credential envelope or deploying a listener.
