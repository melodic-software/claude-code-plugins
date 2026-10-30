---
bump: patch
---

### Fixed

- **`audit-fleet.sh` and `setup-config.sh` no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). The `timeout --help` probe and the existing-entry check read their input through process substitution, so under `set -o pipefail` a supported `--kill-after` or a present entry can no longer read as absent when grep exits before the producer finishes writing.
