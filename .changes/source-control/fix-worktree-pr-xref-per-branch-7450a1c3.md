---
bump: patch
---

### Fixed

- `worktree` status and audit read PRs per worktree branch instead of one capped list of every PR, so older worktrees keep their PR and `superseded` rows are no longer hidden in repositories with many PRs. A failed lookup shows "PR lookup incomplete" rather than no PR.
