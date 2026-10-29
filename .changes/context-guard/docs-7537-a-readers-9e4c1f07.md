---
bump: patch
---

### Changed

- The shared `hook-test-sink.sh` test helper reads the hook-telemetry envelope schema from `docs/contracts/hook-telemetry/`, and from `docs/conventions/hook-telemetry/` only when the new path is absent, ahead of the plugin-contracts move.
