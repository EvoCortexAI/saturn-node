# Saturn-Node Agent Instructions

## Role

Work only on the private Saturn-Node inference service. Treat it as non-operational until implementation and deployment gates are explicitly approved.

## Required context

Read `README.md` and all files in `docs/`, plus Saturn-Control's canonical architecture/MVP plan and the `saturn-mlx-mesh` Node integration boundary.

Saturn-Control owns assignment, policy, public APIs, and compute-lease issuance. `saturn-mlx-mesh` owns in-process MLX execution. EvoEthics owns canonical policy semantics.

## Non-negotiable boundaries

- Accept inference only from authenticated assigned workloads.
- Never accept frontend traffic directly.
- Do not manage Apple Container or execute general tools.
- Do not log prompts, output, credentials, or token material by default.
- Reject unknown, expired, revoked, replayed, wrong-node, wrong-model, and over-budget credentials.
- Bound buffers, concurrency, retries, timeouts, and streams.
- Cancellation leaves no orphan generation.
- Fail closed when identity, policy, runtime, manifest, or contract state is unavailable.

## Contract rule

The canonical compute wire contract is established through `EvoCortexAI/saturn-control#3` and then versioned here. Do not invent incompatible routes, fields, frames, credential formats, or error codes.

Ask before adding dependencies, changing contract/cryptography, adding a listener or `saturn-mlx-mesh`, downloading models, touching launchd/firewall/DNS/credentials, accessing real nodes, or releasing/deploying.
