---
bump: minor
---

### Added

- `/source-control:worktree status` and `audit` work outside a repository: the new `scripts/worktree-discover.sh` resolves every worktree root with the chain `worktree-create.sh` uses, discovers repositories the way `/repo-fleet-hygiene:audit` does with no scope, maps each worktree under a root to its owning repository, and the skill runs the per-repository status and audit for each owner and the root scan with every repository. `cleanup` outside a repository reports candidates grouped by owning repository and removes nothing (#7308).
