---
bump: patch
---

### Changed

- Shared `view-bridge/watch.sh` synced: on an exit-0 wake the watcher also writes its JSON line alone to `.watch-wake.json` (mode 0600) in the data dir, without the background task's stderr and exit footer. The line it prints is unchanged, and the triage board's wake still reads it from the task's output.
