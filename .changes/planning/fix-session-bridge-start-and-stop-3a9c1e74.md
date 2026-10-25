---
bump: patch
---

### Fixed

- The session bridge now reports why its page server failed to start: `ensure-running` keeps the server's stderr in `.<name>-server.log` in the data dir, prints its last lines and exits non-zero.
- `stop` ends the watcher whose command line names the full data-dir path, not one that shares the data dir's last path component, so it no longer stops another topic's watcher.
