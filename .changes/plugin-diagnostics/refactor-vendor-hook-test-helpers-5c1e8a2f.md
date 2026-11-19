---
bump: patch
---

### Changed

- `hooks/plugin-diagnostics-test-helpers.sh` is now a generated copy of the marketplace's `lib/hook-test-helpers.sh`, shared with session-telemetry. The hook test suites no longer read the machine's global or system git config: the helper now sets `GIT_CONFIG_GLOBAL` to `/dev/null` when unset and `GIT_CONFIG_NOSYSTEM=1`. The explanatory comments moved out.
