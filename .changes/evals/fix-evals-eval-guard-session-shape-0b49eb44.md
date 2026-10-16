---
bump: patch
---

### Changed

- plugin-eval: under worktree isolation, a `run` may leave the worktree (`ExitWorktree` and re-enter) only on the user's yes, and a subagent hands the command to its caller, before the user is given a command to paste; records add the 2.1.301 session-shape probes.
- plugin-eval: the run passes `--allow-tools` with the gated tools preflight lists, so cases that run or verify their own work keep `Bash`, `Write` and `Edit`.
