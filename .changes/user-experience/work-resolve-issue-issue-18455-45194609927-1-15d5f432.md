---
bump: patch
---

### Fixed

- The shared config resolver reads the personal override (`<home>/<plugin>.local.*`) from the repository's main checkout when it runs in a linked worktree that has no personal file of its own, so personal settings no longer drop in worktrees.
