---
bump: patch
---

### Fixed

- **`migrate`'s cutover check no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `cutover-check.sh` matches the bundle window with a here-string and the evidence page's AGENTS.md lines through process substitution, and the adherence experiment's scorer does the same, so under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
