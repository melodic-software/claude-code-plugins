---
bump: patch
---

### Fixed

- **`suppression-lint.sh` no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). It checks a parsed record for unparseable lines with a here-string, so under `set -o pipefail` a record it cannot parse can no longer be graded when grep exits before printf finishes writing.
