---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync` no longer aborts with `unbound variable` on bash 4.4 when `fleet-state.sh --fingerprint` fails or prints nothing: `sync-run.sh`'s fallback snapshot key guards `EPOCHREALTIME`, which exists only from bash 5.0.
