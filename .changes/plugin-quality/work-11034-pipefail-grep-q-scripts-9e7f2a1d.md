---
bump: patch
---

### Fixed

- **`collect-standards.sh` and the retirement check no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). The `disable-model-invocation` probe reads the frontmatter through process substitution, and `lib/check-retirements.sh` checks each record's fields with a here-string, so under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
