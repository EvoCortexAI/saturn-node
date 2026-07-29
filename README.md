# Saturn-Node

**Status:** In development - repository bootstrap only  
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

## Bootstrap scope

The first PR provides a Swift 6 package and executable boundary, fail-closed domain seams, deterministic tests, non-secret example configuration, architecture and operations documents, and CI.

It does not provide a listener, credential format, cryptographic verifier, production runtime, model download, launchd service, firewall rule, or SN01 deployment.

The compute wire contract remains blocked on review of `EvoCortexAI/saturn-control#3`. This repository must consume reviewed fixtures rather than invent a competing protocol.

## Verification

```sh
swift package dump-package
swift test
swift run saturn-node
```

The executable intentionally reports that no listener or inference runtime is configured.

## Next gates

1. Import the reviewed workload compute contract and fixtures.
2. Select the credential presentation and verification mechanism through security review.
3. Add deterministic fake-runtime streaming and cancellation tests.
4. Add a narrow `saturn-mlx-mesh` adapter.
5. Add private transport.
6. Request explicit approval before launchd, firewall, credentials, model installation, or SN01 deployment.

## License

This is private EvoCortexAI source. No public license or rights grant is implied by repository access.
