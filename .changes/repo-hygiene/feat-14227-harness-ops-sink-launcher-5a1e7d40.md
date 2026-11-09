---
bump: patch
---

### Changed

- Shared `hook-utils.sh` synced where this plugin carries it (#14227): `HOOK_TELEMETRY_SINK=@harness-ops` sends this plugin's hook telemetry to the harness-ops reference sink, and any other value starting with `@` is reserved and skipped. No other change to this plugin.
