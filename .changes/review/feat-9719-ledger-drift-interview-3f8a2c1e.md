---
bump: patch
---

### Changed

- `view-bridge/wake.sh` is regenerated from `lib/session-bridge/wake.sh`, which now runs an optional `AFTER_APPLY` subcommand named in `session-bridge.conf` between `apply` and the watcher ([#9719](https://github.com/melodic-software/claude-code-plugins/issues/9719)). This plugin's conf names none, so its wake behaves as before.
