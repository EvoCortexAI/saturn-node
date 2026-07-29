# Saturn-Node Workload Compute Contract

**Status:** Proposed v1 contract; implementation is not operational  
**Contract identifier:** `saturn-node.compute.v1`  
**Canonical owner:** `EvoCortexAI/saturn-node`  
**Architecture review gate:** `EvoCortexAI/saturn-control#3`

## Purpose

This contract defines the private compute boundary used by a managed agent container to request bounded MLX inference from its assigned Saturn-Node.

```text
Saturn One or Saturn Container
    -> Saturn-Control
    -> managed agent container
    -> Saturn-Node
    -> saturn-mlx-mesh / MLX
```

Saturn One and Saturn Container never call this API and never receive workload credentials.

## Contract source

The machine-readable source is:

```text
docs/contracts/v1/schema.json
docs/contracts/v1/fixtures.json
docs/contracts/v1/stream.sse
```

Unknown contract versions, fields, event types, problem codes, and credential facts fail closed.

## Transport surface

The v1 private service surface is:

```text
GET  /internal/v1/capabilities
POST /internal/v1/inference
POST /internal/v1/inference/{requestId}/cancel
```

The service binds only to an approved private interface. This document does not authorize a listener, firewall rule, DNS record, launchd service, credential issuer, or SN01 deployment.

### Required request headers

```text
Authorization: Bearer <opaque workload credential presentation>
X-Saturn-Contract-Version: 1
X-Request-ID: <UUID>
```

`POST /internal/v1/inference` also uses:

```text
Content-Type: application/json
Accept: text/event-stream
```

The bearer presentation is opaque to callers. v1 freezes the required semantic claims but deliberately does not choose JWT, PASETO, macaroons, mTLS-only identity, or a custom signed envelope.

## Workload credential semantics

A verified presentation yields the `workloadClaims` object in `schema.json`. It binds:

- credential ID;
- issuer `saturn-control`;
- node-specific audience;
- workload and deployment identity;
- Saturn-Node and model identity;
- context and output limits;
- concurrency, request, and token budgets;
- issue, not-before, and expiry times;
- revocation epoch;
- optional policy and approval references.

The node verifies authenticity before applying the fact-level checks defined here. A frontend token, fleet-wide shared secret, self-declared workload identity, wrong audience, wrong workload, wrong deployment, wrong node, wrong model, expired or revoked credential, stale epoch, replayed request nonce, or exceeded limit is denied.

## Capability discovery

`GET /internal/v1/capabilities` returns only non-sensitive runtime facts:

- contract version;
- node ID and service version;
- runtime state;
- allowed model IDs and their context/output ceilings;
- node concurrency ceiling;
- accepted credential epoch.

It never returns model paths, credentials, private host information, prompts, generated content, or deployment inventory.

## Inference request

`POST /internal/v1/inference` accepts the strict `inferenceRequest` object in `schema.json`.

The request binds:

- UUID request ID matching `X-Request-ID`;
- unique request nonce under the credential;
- workload and deployment identity;
- model ID;
- non-empty input text;
- requested context and output limits;
- absolute request deadline.

The server applies the most restrictive value from the request, verified credential, model manifest, node configuration, and policy. The request ID and nonce are not reusable for changed content or limits.

## Streaming contract

A successful request returns `text/event-stream`.

Permitted event types are:

```text
started
Delta
usage
completed
cancelled
problem
```

The wire value for token output is lowercase `delta`; `Delta` above is descriptive only.

Rules:

1. UTF-8 frames may be fragmented across transport reads.
2. Comment keepalives beginning with `:` are permitted and carry no state.
3. Every event data payload is strict JSON except the final `data: [DONE]` marker.
4. `started` appears exactly once and first.
5. Zero or more `delta` events may follow.
6. At most one `usage` event appears before the terminal event.
7. Exactly one terminal event appears: `completed`, `cancelled`, or `problem`.
8. `completed` and `cancelled` are followed by exactly one `[DONE]` marker.
9. `problem` closes the stream without `[DONE]`.
10. Event sequence numbers are contiguous from zero.
11. Cancellation or disconnect closes generation once and leaves no orphan work.

The canonical success stream is `docs/contracts/v1/stream.sse`.

## Cancellation and disconnect

`POST /internal/v1/inference/{requestId}/cancel` is idempotent for the same authorized workload and request.

- An active request returns `202` with state `cancellation_requested`.
- A previously cancelled request may return the same terminal state.
- An unknown or unauthorized request does not disclose whether another workload owns it.
- Client disconnect is treated as cancellation unless the request has already reached a terminal event.
- The runtime receives one cancellation signal and the stream emits at most one terminal event.

## Deadlines and capacity

The effective deadline is the earliest of:

- request `deadlineAt`;
- credential expiry;
- policy deadline;
- node maximum duration.

Idle, total, and cancellation-grace timeouts are service configuration, not caller-controlled fields. Timeout and saturation use typed problem codes. A retry hint is permitted only when retry is safe and bounded.

## Stable problem codes

The v1 problem vocabulary is:

```text
contract_version_unsupported
malformed_request
unauthenticated
unauthorized
wrong_audience
wrong_workload
wrong_deployment
wrong_node
model_not_allowed
credential_not_yet_valid
credential_expired
credential_revoked
credential_replayed
stale_credential_epoch
request_limit_exceeded
token_budget_exceeded
node_saturated
request_timeout
cancelled
internal_failure
```

HTTP status, stable code, request ID, and optional bounded retry hint are represented by the `problem` definition in `schema.json`.

## Usage evidence and logging

The node emits metadata-only usage evidence containing request, workload, deployment, node, model, timestamps, token counts, outcome, and applicable policy or approval references.

Standard logs and audit events must not contain:

- input text or prompts;
- generated text;
- credentials or authorization headers;
- model files or private filesystem paths;
- private endpoint or host inventory.

## Versioning

- The request header and body version must agree.
- Additive optional fields require a reviewed minor contract revision.
- New required fields, changed meanings, removed values, or changed event ordering require a new major contract directory.
- A v1 implementation rejects unknown fields rather than guessing.
- Saturn-Control, agent-runtime, and Saturn-Node tests must consume the same reviewed fixtures.

## Non-goals

This contract does not define Apple Container lifecycle, agent tools, frontend APIs, general workflow execution, public Saturn-Node exposure, automatic multi-node scheduling, distributed mesh control, normative ethics, or the cryptographic token format.