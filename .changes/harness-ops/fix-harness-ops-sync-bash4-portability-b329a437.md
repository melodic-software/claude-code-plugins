---
bump: patch
---

### Fixed

- `/harness-ops:plugins` scripts run on bash 4.x: `cache-content-check.sh` no longer uses a negative array subscript (bash 4.3+), and `sync-run.sh` no longer aborts under `set -u` on bash before 5.0 when `fleet-state.sh --fingerprint` prints nothing.
