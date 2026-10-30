---
bump: patch
---

### Fixed

- **`repo-sweep`'s `tick.sh` no longer pipes into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). It reads the edited pull request body through process substitution when it confirms the ticked line landed, so under `set -o pipefail` a landed edit can no longer be reported as "edit did not land" when grep exits before the producer finishes writing.
