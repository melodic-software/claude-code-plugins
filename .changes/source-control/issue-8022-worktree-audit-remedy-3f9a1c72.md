---
bump: minor
---

### Added

- **`worktree audit` Step 2b runs the recreate-and-reap remedy through one script.** `scripts/reap-orphaned-plugin-records.sh` takes the individually confirmed paths and, for each in order, runs the chain Step 2b used to hand out (plain `mkdir`, the reap helper with `--dry-run` and then for real, removal of the path's `.claude`, `rmdir`). It stops at the first failure naming the path and step, and keeps every guard: an existing path is refused without reaping, the reap helper still checks its own cwd, and only the directory the script created is removed.
