---
bump: minor
---

### Added

- `worktree-claim.sh stale --batch --repo-dir DIR` reads NUL-delimited paths on stdin and prints one `exit<TAB>path<TAB>note` row per path, carrying the exit code and note single-path `stale` gives for it. The worktree list is parsed once and the transcript directory scanned once per run, and a clean absolute path to an existing directory starts no subshell, so the process count stays the same as worktrees and paths grow. `/source-control:worktree cleanup` identifies its candidates with one batch per repository in Step 2 instead of one `stale` call per locked worktree; each locked candidate's removal still waits on a fresh single-path `stale` just before its release (#10562).

### Fixed

- `worktree-discover.sh` lists every worktree a listed repository registers below a resolved root, not only the root's direct children. A worktree nested inside another worktree's `.work/`, or under a plain directory in the root, now gets a `worktree` row with its repository, so the cross-repository `status` and `cleanup` inventory it (#10562).
