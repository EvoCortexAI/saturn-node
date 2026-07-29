# Operations

**Current state:** No deployable service exists.

Bootstrap verification:

```sh
swift package dump-package
swift test
swift run saturn-node
```

Before deployment, define private binding, non-secret configuration loading, manifest integrity, health/readiness, graceful shutdown, bounded logs, launchd lifecycle, restart/rollback, key rotation/revocation refresh, pressure handling, and incident-safe diagnostics.

Do not install launchd units, change firewall rules, provision credentials, download production models, bind a listener, or alter SN01 from bootstrap work.
