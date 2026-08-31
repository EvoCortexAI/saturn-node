# Architecture

**Type:** architecture
**Status:** binding-after-merge for the `0.1.x` contract diagrams
**Authority:** diagrams describe the fail-closed boundary; they do not authorize SN01
**Schema:** docs/MARKDOWN-SCHEMA.md

Saturn-Node `0.1.x` views. Issue #4 remains open.

## Saturn execution plane

```mermaid
flowchart LR
    One[Saturn One]
    Container[Saturn Container]
    Control[Saturn-Control]
    Agent[Managed agent]
    Node[Saturn-Node]
    Mesh[saturn-mlx-mesh]
    MLX[MLX]

    One -->|client API only| Control
    Container -->|client API only| Control
    Control -->|assignment + lease| Agent
    Agent -->|workload-authenticated request| Node
    Node -->|in-process adapter| Mesh
    Mesh --> MLX

    One -. forbidden .-> Node
    Container -. forbidden .-> Node
```

## Enforcement boundary

```mermaid
flowchart TB
    Req[Inference request]
    Claim[Workload claim]
    Lease[Compute lease]
    PEP[Saturn-Node PEP]
    Closed[UnavailableInferenceRuntime]
    Sim[Simulated mesh path]
    Real[MeshModelInferenceRuntime]
    Mesh[saturn-mlx-mesh]

    Req --> PEP
    Claim --> PEP
    Lease --> PEP
    PEP -->|default| Closed
    PEP -->|CI| Sim --> Mesh
    PEP -->|opt-in --real-smoke| Real --> Mesh
    PEP -->|invalid / expired| Deny[Fail closed]
```

Default composition is fail-closed. The ordinary executable does not construct real MLX.

## Mesh dependency

```mermaid
flowchart LR
    NodePkg[Saturn-Node Package.swift]
    Tag["mesh tag 0.2.0 @ 9aab96a2"]
    Semver[".upToNextMinor from 0.2.0"]
    NodeTag["Node tag 0.1.0 @ ba5f7c61"]
    Evidence["hardware evidence 8ce1d6f6"]

    Tag --> Semver
    NodePkg --> Semver
    NodeTag -. shipped revision pin; do not retarget .-> Evidence
    Evidence -. provenance only .-> Tag
```

Published mesh tag `0.2.0` is `9aab96a2e24817fbb1898f8c133ad44469986805`. Current Node `main` consumes `.upToNextMinor(from: "0.2.0")`. Node `0.1.0` keeps the revision pin it shipped; do not retarget that tag.

## Version identity

```mermaid
flowchart TB
    Policy[docs/VERSIONING.md]
    Procedure[docs/RELEASING.md]
    Record[docs/releases/0.1.0.md]
    Log[CHANGELOG]
    Tag["Git tag 0.1.0"]
    SHA["ba5f7c61"]

    Policy --> Procedure --> Record --> Tag
    Log --> Tag
    Tag --> SHA
    Log -. is not .-> Tag
    Record -. is not .-> Tag
```

## Release procedure

```mermaid
flowchart TD
    A[Choose 0.x.y] --> B[Update CHANGELOG + docs/releases]
    B --> C[Merge prep PR to main]
    C --> D[Record exact main SHA]
    D --> E[CI green on that SHA]
    E --> F{Founder approves version + SHA?}
    F -->|no| G[Stop. No tag]
    F -->|yes| H[Tag on that SHA]
    H --> I[GitHub release records SHA]
```

No tag authorizes a listener or SN01.

## Doc architecture

```mermaid
flowchart TB
    Schema[MARKDOWN-SCHEMA]
    Arch[ARCHITECTURE]
    Ver[VERSIONING]
    Rel[RELEASING]
    Rec[releases/0.1.0]
    Log[CHANGELOG]
    Contract[COMPUTE-CONTRACT]
    Accept[ACCEPTANCE-TEST]

    Schema --> Arch
    Schema --> Ver --> Rel --> Rec --> Log
    Arch --> Contract
    Arch --> Accept
```
