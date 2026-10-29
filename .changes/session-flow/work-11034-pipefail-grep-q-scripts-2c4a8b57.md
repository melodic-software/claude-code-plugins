---
bump: patch
---

### Fixed

- **The per-project state key no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `lib/state-key.sh` checks the remote identity with a here-string instead of `printf | grep -q`, so under `set -o pipefail` a valid identity can no longer be read as invalid and keyed by hash when grep exits before printf finishes writing.
