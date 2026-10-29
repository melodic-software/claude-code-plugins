---
bump: patch
---

### Fixed

- **`remove-path.sh` no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). It reads `rm --version` through process substitution, so under `set -o pipefail` a coreutils `rm` can no longer be missed, which would drop `--one-file-system`, when grep exits before `rm` finishes writing.
