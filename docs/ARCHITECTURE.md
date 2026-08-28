# Architecture

**Type:** architecture
**Status:** binding-after-merge for the `0.1.x` contract diagrams
**Authority:** diagrams describe the fail-closed boundary; they do not publish a tag or authorize SN01
**Schema:** docs/MARKDOWN-SCHEMA.md

These flowcharts are the architecture views for Saturn-Node `0.1.x`. Issue #4 remains open.

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

Default composition is fail-closed. Real MLX is not constructed by the ordinary executable.

## Mesh dependency

```mermaid
flowchart LR
    NodePkg[Saturn-Node Package.swift]
    Pin["revision 8ce1d6f6 hardware pin"]
    Prep["mesh main 9aab96a2 after #15"]
    Tag["mesh tag 0.2.0"]
    Semver[".upToNextMinor from 0.2.0"]

    NodePkg --> Pin
    Prep -. docs candidate, not a tag .-> Tag
    Tag --> Semver
    Pin -. replace only after tag .-> Semver
```

`saturn-mlx-mesh` PR #15 merged to `main` at `9aab96a2e24817fbb1898f8c133ad44469986805`. That SHA is the mesh `0.2.0` *candidate*. It is not the tag. Node keeps revision `8ce1d6f6d6f5304f526019a5b5bcbf3f2b2f783e` until the tag exists.

## Version identity

```mermaid
flowchart TB
    Policy[docs/VERSIONING.md]
    Procedure[docs/RELEASING.md]
    Record[docs/releases/0.1.0.md]
    Log[CHANGELOG 0.1.0]
    Merge[merge this prep PR]
    SHA[main commit SHA]
    Approve[Founder approval]
    Tag["Git tag 0.1.0"]
    GH[GitHub release + SHA]

    Policy --> Procedure
    Record --> Merge
    Log --> Merge
    Merge --> SHA --> Approve --> Tag --> GH

    Log -. is not .-> Tag
    Record -. is not .-> Tag
    Merge -. does not create .-> Tag
```

## Release procedure

```mermaid
flowchart TD
    A[Choose 0.1.0] --> B[Update CHANGELOG + docs/releases]
    B --> C[Merge prep PR to main]
    C --> D[Record exact main SHA]
    D --> E[CI green on that SHA]
    E --> F{Founder approves version + SHA?}
    F -->|no| G[Stop. No tag]
    F -->|yes| H[Tag 0.1.0 on that SHA]
    H --> I[GitHub release records SHA]
    I --> J[Verify tag resolves to SHA]
    J --> K[After mesh 0.2.0 tag: separate pin-switch PR]
```

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
