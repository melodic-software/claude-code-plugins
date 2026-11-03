---
bump: patch
---

### Fixed

- The `upstream-apply-changelog` model job resolves its model, effort and turns from a new
  `apply-changelog` skill slot of its lane (route `code-fix`), in place of `model-route:
  resolve-issue`, which resolve-config refuses as no run route, so every release run failed before
  the model.
- The lane's runs wait in line (`queue: max`) instead of a newer run cancelling a pending one, so
  two dispatches in quick succession both run.
