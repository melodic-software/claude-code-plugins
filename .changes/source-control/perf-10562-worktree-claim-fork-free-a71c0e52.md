---
bump: minor
---

### Added

- `worktree-claim.sh stale --batch` reads NUL-delimited paths on stdin and prints one `<exit>\t<path>\t<note>` row per path, each the exit code and line `stale <path>` gives, from one worktree-list read and one transcript scan per run. The run exits 0 once every row is printed, and 2 or 5 only when it fails as a whole, which leaves every path unproven. `/source-control:worktree cleanup` takes the lock-liveness verdicts of every locked candidate from one batch run, in Step 2 and again after the Step 4 confirmation, and keeps the single-path `stale <path>` re-check after an owner-is-done confirmation.

### Fixed

- `worktree-claim.sh` no longer forks once per registered worktree. Each worktree's path was canonicalized through three command substitutions, so every verb, and the PostToolUse add-claim hook, took about 4 s in a repository with 1,243 linked worktrees. The collapse now runs only for a path with a `//`, `.` or `..` segment or a trailing slash, the physical path comes from an in-shell `cd -P`, and siblings under one non-symlink parent share one resolution. A spawn-budget suite fails if the process count grows with the worktree count.
- `worktree-discover.sh` lists a worktree a repository registers deeper under a worktree root (under a grouping directory, or nested in another worktree's `.work/`), with that repository as its owner. Its scan reads only a root's direct children, so the cross-repository `status` and `cleanup` never inventoried those worktrees.
