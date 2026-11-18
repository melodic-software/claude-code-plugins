---
bump: patch
---

### Changed

- The shared `worktree-root-resolve.sh` runs its git calls through `hook::git_untrusted` when a caller loaded `hook-utils.sh` and defined no `_worktree_root_git`. The fleet audit defines `_worktree_root_git`, so it behaves as before.
