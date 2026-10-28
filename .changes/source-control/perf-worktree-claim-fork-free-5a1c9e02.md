---
bump: patch
---

### Changed

- `worktree-claim.sh` resolves each registered worktree's path without starting a subshell in the common case (a clean absolute path to an existing directory), and siblings under one non-symlink parent share a single `cd -P`. Every verb, and the add-claim hook, used to fork three or four times per registered worktree. In a repository with 1,243 linked worktrees one `stale` call fell from 3.63 s to 0.44 s, with `report` output byte-identical across all 1,244 rows (#10562).
