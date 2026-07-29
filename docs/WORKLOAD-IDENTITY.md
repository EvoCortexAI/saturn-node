# Workload Identity

**Status:** Proposed v1 semantic claims; credential envelope not selected

A caller is a managed agent workload assigned by Saturn-Control. Frontend identity, a fleet-wide shared secret, and self-declared workload identity are invalid at this boundary.

## Required claims

The reviewed semantic claim set is defined by `workloadClaims` in `docs/contracts/v1/schema.json` and includes:

- `credentialId`;
- issuer `saturn-control`;
- audience `saturn-node:<nodeId>`;
- `workloadId` and `deploymentId`;
- `nodeId` and allowed `modelId`;
- maximum context and output tokens;
- maximum concurrent requests;
- request and token budgets;
- `issuedAt`, `notBefore`, and `expiresAt`;
- revocation `epoch`;
- optional policy and approval references.

## Verification order

Before inference, Saturn-Node must:

1. verify credential authenticity and trusted issuer;
2. reject an unsupported contract version;
3. verify node-specific audience;
4. verify workload and deployment binding;
5. verify node and model binding;
6. verify not-before, expiry, and bounded clock skew;
7. verify current epoch and explicit revocation state;
8. reject a replayed request ID or request nonce;
9. enforce context, output, concurrency, request, and token limits;
10. record metadata-only correlation and outcome.

A failed check is terminal for that request. Evaluator, verifier, or revocation-state unavailability is not permission.

## Presentation mechanism

The API uses an opaque bearer presentation. The semantic claims are frozen independently from their cryptographic envelope.

Selection among JWT, PASETO, macaroons, mTLS-bound credentials, or a custom signed envelope requires a separate security review covering:

- algorithm and key restrictions;
- issuer and audience validation;
- key discovery and rotation;
- revocation and epoch propagation;
- replay resistance;
- clock-skew bounds;
- credential storage in agent workloads;
- downgrade resistance;
- incident rollback.

No production credential issuer or verifier is authorized by this document.