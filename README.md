# Saturn-Node

**Status:** In development - service boundary and proposed v1 contract only  
**Visibility:** Private  
**Operational service:** Not implemented

Saturn-Node is the private, workload-authenticated MLX inference service in the Saturn execution plane.

```text
Saturn One or Saturn Container
    -> Saturn-Control
    -> managed agent container
    -> Saturn-Node
    -> saturn-mlx-mesh / MLX
```

Frontends never call Saturn-Node directly. Saturn-Control assigns compute and issues short-lived, deployment-scoped credentials to an authorized agent workload.

## Ownership

Saturn-Node owns private workload-authenticated inference transport, credential verification and revocation state, model allowlisting, pinned manifests, streamed inference, cancellation, bounded resource limits, metadata-only usage evidence, and service recovery.

It does not own Apple Container lifecycle, Saturn-Control orchestration, agent tools, frontend APIs, public exposure, distributed-mesh research, or canonical ethical principles.

## Current repository state

The repository contains:

- a Swift 6 package and fail-closed executable boundary;
- typed model-manifest, workload-claim, authorization, request, event, and runtime seams;
- deterministic bootstrap tests;
- a proposed workload compute contract under `docs/contracts/v1/`;
- strict JSON fixtures and a fragmented-SSE fixture;
- a standard-library validator executed by CI;
- non-secret example configuration and operations guidance.

It does not provide a listener, cryptographic credential verifier, production runtime, model download, launchd service, firewall rule, or SN01 deployment.

## Contract review

The proposed private compute contract is:

- `docs/COMPUTE-CONTRACT.md`;
- `docs/WORKLOAD-IDENTITY.md`;
- `docs/contracts/v1/schema.json`;
- `docs/contracts/v1/fixtures.json`;
- `docs/contracts/v1/stream.sse`.

The architecture review gate remains `EvoCortexAI/saturn-control#3`. The contract is not operational until it is reviewed, merged, implemented by Saturn-Node, and consumed by deterministic Saturn-Control and agent-runtime tests.

The semantic claims are independent of their future cryptographic envelope. This repository does not yet choose JWT, PASETO, macaroons, mTLS-only identity, or a custom signed envelope.

## Verification

```sh
swift package dump-package
python3 scripts/validate_saturn_node_contract.py
swift test
swift run saturn-node
```

The executable intentionally reports that no listener or inference runtime is configured.

## Next gates

1. Review and merge the workload compute contract and fixtures.
2. Update Swift types and tests to consume the frozen v1 fixtures.
3. Select the credential presentation and verification mechanism through security review.
4. Add deterministic fake-runtime streaming and cancellation tests.
5. Add a narrow `saturn-mlx-mesh` adapter.
6. Add private transport.
7. Request explicit approval before launchd, firewall, credentials, model installation, or SN01 deployment.

## License

This is private EvoCortexAI source. No public license or rights grant is implied by repository access.
