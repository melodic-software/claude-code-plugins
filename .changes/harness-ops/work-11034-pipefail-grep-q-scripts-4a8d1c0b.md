---
bump: patch
---

### Fixed

- **The lane launcher and the shared libraries no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `lane-launcher.sh` reads the `timeout --help` probe, the App installation's repository list and the target lane names through process substitution, and `lib/check-retirements.sh` and `lib/state-key.sh` use here-strings. Under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
