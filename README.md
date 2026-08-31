# Saturn-Node

**Status:** In development — fail-closed service boundary, published `0.1.0`  
**Operational service:** Not implemented  
**License:** Apache License 2.0 ([`LICENSE`](LICENSE), [`NOTICE`](NOTICE))

Private, workload-authenticated MLX inference service. Frontends never call it. Saturn-Control assigns compute and issues the short-lived lease; `saturn-mlx-mesh` runs MLX in-process.

Diagrams: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Versioning: [`docs/VERSIONING.md`](docs/VERSIONING.md).

## Boundary

Owns private inference transport, credential verification, model allowlist, pinned manifests, stream, cancel, resource bounds, metadata-only evidence, recovery.

Does not own Container lifecycle, Control orchestration, agent tools, frontend APIs, ACP, distributed-mesh research, or EvoEthics principles.

A client-visible `cancelled` state is not proof. Native stop, empty active set, reclaimed request resources, and a later successful request are required on Apple hardware. See [`docs/ACCEPTANCE-TEST.md`](docs/ACCEPTANCE-TEST.md).

## Repository state

Present: Swift 6.3 / macOS 26 package, typed seams, contract fixtures + CI validator, `MeshInferenceRuntimeAdapter` (sim + opt-in real MLX), `--real-smoke` / sustained acceptance runner.

Absent: production listener, production verifier, default real-runtime composition, launchd, firewall, SN01 deploy.

Default composition is `UnavailableInferenceRuntime`. Real MLX is constructed only by explicit hardware-smoke invocation.

## Mesh pin

| Field | Value |
|-------|--------|
| Model | `mlx-community/Qwen3-8B-4bit` |
| Manifest example | `config/model-manifest.example.json` |
| Mesh package | `.upToNextMinor(from: "0.2.0")` |
| Mesh `0.2.0` SHA | `9aab96a2e24817fbb1898f8c133ad44469986805` |
| Node `0.1.0` SHA | `ba5f7c61d87a2e111d9e1b70d78bb74b964a2454` (still the revision pin it shipped) |
| Procedure | `saturn-mlx-mesh` → `Docs/ACCEPTANCE-MODEL.md` |

32B is not the KF path. Do not retarget `0.1.0`.

## Hardware smoke

```sh
swift run saturn-node --real-smoke
swift run saturn-node --real-smoke --cancel-recovery
swift run saturn-node --real-smoke --requests 20 --cancellations 5
```

Metadata-only. `--show-content` is local-debug. One-shot pass is not the sustained gate. Sustained = 20 ordinary + 5 cancel/quiesce/recover cycles in one process and one model load, then a fresh-process restart. None of these open a listener.

The adapter admits only a future `deadlineAt`, maps mesh timeout to `requestTimedOut`, and cancels in-flight generation when the wall clock crosses `deadlineAt`. Explicit cancel before the deadline stays `.cancelled`.

## Contract

- `docs/COMPUTE-CONTRACT.md`
- `docs/WORKLOAD-IDENTITY.md`
- `docs/contracts/v1/`

Node verifies; Control issues. Do not add a second session or compute-credential issuer here.

## Verify

```sh
swift package dump-package
python3 scripts/validate_saturn_node_contract.py
swift test
swift run saturn-node
```

## Next gates (issue #4)

1. Record basic + sustained M4 Pro evidence for Qwen3-8B-4bit.
2. Freeze credential envelope / founder ADR.
3. Production verifier + private transport after security review.
4. Founder approval before listener, launchd, firewall, or SN01.

In-flight `deadlineAt` is already implemented in-library. It does not authorize transport.
