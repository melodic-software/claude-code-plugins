---
bump: patch
---

### Fixed

- **`resolve-config.sh` and the `test-scan` hook no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). The resolver finds an unknown adapter's line through process substitution, so under `set -o pipefail` a found line can no longer come back as a failure, which left the error without its file and line, when `grep -m1` exits before `sed` finishes writing. The hook's config-error lookup takes the same form; its captured text was already correct.
