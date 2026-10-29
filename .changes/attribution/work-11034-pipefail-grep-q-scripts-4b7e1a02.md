---
bump: patch
---

### Fixed

- **Retirement-manifest validation no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `lib/check-retirements.sh` checks each record's id, date, version, path and heading with a here-string instead of `printf | grep -q`, so under `set -o pipefail` a valid field can no longer be rejected, or a `..` path missed, when grep exits before printf finishes writing.
