---
bump: patch
---

### Fixed

- The pre-commit content check no longer blocks a merge commit because of a secret or
  machine-specific path that the merged branch already holds, such as a line that reached `main`
  through a pull request merged on GitHub. A merge is now judged on the lines its conflict resolution
  adds, the way the pre-push content check already judges it. A secret or path that the resolution
  adds still blocks.
