---
bump: minor
---

### Added

- `/source-control:worktree audit` reports, as an error, a registered worktree whose path lies inside a different repository's work tree, naming the owning repository, the containing repository and the remove command, and counts the `UNCLAIMED` worktrees outside the resolved worktree root (`worktree-claim.sh report --root`).
