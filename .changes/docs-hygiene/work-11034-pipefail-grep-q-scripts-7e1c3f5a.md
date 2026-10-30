---
bump: patch
---

### Fixed

- **`audit-progressive-disclosure`'s detector no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `detect.sh` checks a rule file's frontmatter for `paths:` with a here-string, so under `set -o pipefail` a path-scoped rule can no longer be graded always-loaded when grep exits before printf finishes writing.
