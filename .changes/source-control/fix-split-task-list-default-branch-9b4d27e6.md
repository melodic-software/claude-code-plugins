---
bump: patch
---

### Fixed

- The pr-merge gate reads admission's `task-list` for a size-split sub-issue from `admission-rules.json` at the repository's default branch, as pr-verify reads it from main's checkout, instead of at the pull request's base branch. A failed read of the default branch refuses `verify:unreadable`.
