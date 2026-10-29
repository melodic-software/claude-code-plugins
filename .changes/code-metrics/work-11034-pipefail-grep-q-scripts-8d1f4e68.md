---
bump: patch
---

### Fixed

- **`audit-coverage` and the per-project state key no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `audit-coverage.sh` detects the artifact format by reading `head` through process substitution, and `lib/state-key.sh` checks the remote identity with a here-string, so under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
