---
bump: minor
---

### Added

- The view bridge records the plugin version and a hash of its own source at server start, and `view-bridge.sh ensure-running` restarts a running server whose recorded build differs from the installed plugin's, saying so on stderr. `watch.sh` prints a `note:` line on stderr before it polls when the server's recorded plugin version differs from the installed one.
