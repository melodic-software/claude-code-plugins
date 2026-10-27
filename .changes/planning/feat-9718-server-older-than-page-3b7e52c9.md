---
bump: minor
---

### Added

- The interview page server records the plugin version and a hash of its own source at start, and `/api/state` reports them as `pluginVersion` and `sourceHash`. The page compares them with the build stamped into it when served and, when its server is older, shows "This page's server is older than the page. Run ensure-running to restart."
- `round.sh ensure-running` restarts a running page server whose recorded plugin version or source hash differs from the installed plugin's, on its port and with its user settings file, posting no finish, and says so on stderr. The shared session's `share.sh ensure-running` and the view bridge's `ensure-running` restart such a server the same way.
- `watch.sh` prints a `note:` line on stderr before it polls when the server's recorded plugin version differs from the installed one.
