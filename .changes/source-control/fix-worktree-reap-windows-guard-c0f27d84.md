---
bump: patch
---

### Fixed

- `worktree-reap.sh` refuses to reap or dry-run under Windows bash (Git Bash, MSYS, Cygwin) with exit 3: its `/proc` lists only that bash's own processes, so a native Windows process holding a worktree was invisible. `--report` still runs.
- `worktree-reap.sh` runs without GNU `realpath -e`, `find -printf` or `timeout`, falling back to `cd -P`, `readlink` and a shell watchdog, and takes its `--log` lock through `perl` when `flock` is missing; with neither it refuses with exit 2. Each fallback taken is named in the run's output, and the usage text now lists the exit codes.
- The Windows test lane runs the `worktree-reap`, `worktree-include` and `landed-work` suites; two `worktree-include` cases Windows cannot represent skip there with their reason.
