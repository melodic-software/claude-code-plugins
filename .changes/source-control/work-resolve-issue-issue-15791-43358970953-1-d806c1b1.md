---
bump: minor
---

### Added

- `/source-control:pull-request ready`: `pr-worktree.sh` and `verify-gate.sh` take `--dir <checkout>`, as `target-repo.sh` does. `pr-worktree.sh` reads the PR's head and lists worktrees in that checkout, and `verify-gate.sh` finds the common git directory there (`READY_VERIFY_DIR` still wins). The ready phase's command lines pass `--dir`, so a session that works on a repository by absolute path, with its shell in another checkout, finds the PR's worktree and the verify record. Without `--dir`, both scripts use the current directory as before.
