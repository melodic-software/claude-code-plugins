---
bump: patch
---

### Fixed

- **The legacy frontier-tier signal and the Linear schema fidelity check no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `legacy-frontier-tier-signal.sh` matches the body with a here-string, and `fidelity.sh` reads the normalized adapter source and validator through process substitution, so under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
