---
bump: patch
---

### Fixed

- **The harness-config audit scripts no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `audit-engine.sh` scans the settings file for a secret-shaped value through process substitution, `automode-entry-diff.sh` matches each rule with a here-string, and `lib/check-retirements.sh` and `lib/state-key.sh` do the same for their field checks. Under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
