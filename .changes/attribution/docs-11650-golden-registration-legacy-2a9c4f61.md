---
bump: patch
---

### Changed

- `/attribution:audit`'s golden-case loop says the golden set stays registered in the skill's existing `evals/evals.json`, the file the orphaned-fixtures gate reads for it, and points new behavior cases at the plugin suite (`plugins/attribution/evals/<case>/case.yaml`, checked by `/evals:validate`).
