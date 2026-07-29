# Workload Identity

A short-lived compute credential must bind credential, workload, deployment, node, model, context/output limits, concurrency, request/token budget, issue/expiry times, revocation or epoch state, and applicable policy/approval reference.

Before inference, verify authenticity, audience/node, workload/deployment, time/revocation/replay state, model, and all limits; then record metadata-only correlation.

No frontend token, fleet-wide shared secret, or self-declared workload identity is accepted.

The bootstrap does not choose JWT, PASETO, macaroons, mTLS-only identity, or a custom signed envelope. That requires contract and security review.
