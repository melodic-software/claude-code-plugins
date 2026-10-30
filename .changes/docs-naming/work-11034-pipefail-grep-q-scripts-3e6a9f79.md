---
bump: patch
---

### Fixed

- **The docs-naming scripts no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `setup-check.sh`, `inventory.sh`, `emit-gate.sh` and `lib/check-retirements.sh` match names against the casing regex, the folded directory list and the retirement fields with a here-string instead of `printf | grep -q`, so under `set -o pipefail` a match can no longer read as a miss when grep exits before printf finishes writing.
