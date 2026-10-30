---
bump: patch
---

### Fixed

- **`check-skill.sh` no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). The mutate and read-only description checks, the moved-trigger check and the `metadata.category` note read their input from a here-string or process substitution, so under `set -o pipefail` a match can no longer read as a miss when grep exits before the producer finishes writing.
