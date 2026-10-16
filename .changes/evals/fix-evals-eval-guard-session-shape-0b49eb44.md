---
bump: patch
---

### Changed

- plugin-eval: under worktree isolation, run the CLI from a session shape the guard allows (`ExitWorktree` and re-enter, or hand the command to a non-isolated caller) before handing the user a command; records add the 2.1.301 session-shape probes.
- plugin-eval: the run passes `--allow-tools` with the gated tools preflight lists, so cases that run or verify their own work keep `Bash`, `Write` and `Edit`.
