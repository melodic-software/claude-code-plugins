---
bump: minor
---

### Added

- `/work-items:work` CI mode continues an earlier run's branch when the runner's `issue.json` carries `resume` (the branch, why that run ended, its commit subjects and changed files): it reads the committed work, does not redo it, and finishes what is left.
