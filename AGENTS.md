# Saturn-Node Agent Instructions

## Role

Work only on the private Saturn-Node inference service. Treat it as non-operational until implementation and deployment gates are explicitly approved.

## Required context

Read `README.md` and all files in `docs/`, plus Saturn-Control's canonical architecture/MVP plan and the `saturn-mlx-mesh` Node integration boundary.

Saturn-Control owns assignment, policy, public APIs, and compute-lease issuance. `saturn-mlx-mesh` owns in-process MLX execution. EvoEthics owns canonical policy semantics.

## Toolchain baseline

- Swift tools: **6.3**
- Package deployment floor: **macOS 26**
- `saturn-mlx-mesh` must be pinned to an exact reviewed merge SHA for Node hardware acceptance.

Do not lower the platform or toolchain baseline without an explicit compatibility decision.

## Non-negotiable boundaries

- Accept inference only from authenticated assigned workloads.
- Never accept frontend traffic directly.
- Do not manage Apple Container or execute general tools.
- Do not log prompts, output, credentials, or token material by default.
- Reject unknown, expired, revoked, replayed, wrong-node, wrong-model, and over-budget credentials.
- Bound buffers, concurrency, retries, timeouts, and streams.
- Cancellation leaves no orphan generation.
- Fail closed when identity, policy, runtime, manifest, or contract state is unavailable.

## Hardware acceptance

Ordinary CI remains deterministic and must not download model weights. Real MLX execution is explicit and runs only on an approved Apple Silicon acceptance host:

```sh
swift run saturn-node --real-smoke
swift run saturn-node --real-smoke --cancel-recovery
```

Standard acceptance output must remain metadata-only. `--show-content` is local-debug only and must not be used in captured acceptance artifacts.

A passing hardware smoke does not authorize a listener, production composition, credentials, launchd installation, firewall changes, or deployment. Follow `docs/ACCEPTANCE-TEST.md` for the remaining gates.

## Contract rule

The canonical compute wire contract is established through `EvoCortexAI/saturn-control#3` and then versioned here. Do not invent incompatible routes, fields, frames, credential formats, or error codes.

Ask before adding dependencies, changing contract/cryptography, adding a listener, changing the mesh dependency beyond an approved pin, downloading models outside an explicit hardware acceptance run, touching launchd/firewall/DNS/credentials, accessing real nodes, or releasing/deploying.
