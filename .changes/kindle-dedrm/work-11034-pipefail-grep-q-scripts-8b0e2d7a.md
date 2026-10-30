---
bump: patch
---

### Fixed

- **The `manage` scripts no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `lock-updates.sh`, `status.sh` and `sync-finalize.sh` read the PowerShell output through process substitution, so under `set -o pipefail` a DENY entry or a running Kindle can no longer read as absent when grep exits before PowerShell finishes writing.
