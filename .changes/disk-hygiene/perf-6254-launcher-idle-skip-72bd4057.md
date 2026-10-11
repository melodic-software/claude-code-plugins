---
bump: patch
---

### Changed

- **The guard-launch monitor's Stop row no longer starts bash in a session whose guard never launched.** The launcher now makes the `--skip-unless-marker` test itself, with the same explicit marker root: it skips only when the marker directory exists and holds no marker for the session. A missing session id, a missing directory or a stalled payload runs the monitor, and the script keeps its own check. Shared `exec-bash.mjs` synced.
