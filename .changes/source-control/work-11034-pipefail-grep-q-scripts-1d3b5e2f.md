---
bump: patch
---

### Fixed

- **`resolve-remote.sh` and the retirement check no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). The `origin` lookup reads the remote list through process substitution, and `lib/check-retirements.sh` checks each record's fields with a here-string, so under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
