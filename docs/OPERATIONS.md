# Operations

**Current state:** No deployable service exists.

Bootstrap verification:

```sh
swift package dump-package
swift test
swift run saturn-node
```

## Model pin (not deployment)

KF / mesh#1 primary model identity: `mlx-community/Qwen3-8B-4bit`
(see mesh `AcceptanceModelPin` and `Docs/ACCEPTANCE-MODEL.md`).

Example allowlist shape: `config/model-manifest.example.json`.
Runtime and weight **revisions** remain placeholders until hardware evidence is recorded.

Before deployment, define private binding, non-secret configuration loading, manifest integrity, health/readiness, graceful shutdown, bounded logs, launchd lifecycle, restart/rollback, key rotation/revocation refresh, pressure handling, and incident-safe diagnostics.

Do not install launchd units, change firewall rules, provision credentials, download production models, bind a listener, or alter SN01 from bootstrap work.
