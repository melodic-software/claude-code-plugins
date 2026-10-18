---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync` no longer leaves an `ask` pick installed but off when a run is interrupted between the install and the enable. `sync-run.sh` journals the pick in `pending-enable.txt` (beside the run journals under the plugin data directory) before installing it and clears the entry once the enable lands. The next sync enables a leftover pick that is installed at user scope and off, lists it in the digest's `pending_enable[]`, and drops an entry whose install never finished. A user-set `enabledPlugins: false` with no entry is never re-enabled.
