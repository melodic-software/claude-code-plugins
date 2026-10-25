---
bump: patch
---

### Changed

- The settings-token baseline is empty: its one row, for `/evals:plugin-eval`, is gone now that the skill states the fallback for its settings token, so every settings token used as a condition with no fallback fails check 31 when this marketplace checks its own skills.
