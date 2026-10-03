---
type: llm
arm: both
---

PASS if the answer prints the `claude plugin eval` command for the user to paste into a terminal outside Claude Code, with paths that resolve the same from any directory: an absolute target and an absolute `--json` path (a placeholder standing for the absolute worktree path counts, and so does a `~` path), or a `cd` to the absolute worktree path followed by the command.

FAIL if a path is relative with no such `cd`, or is built from `$PWD` (that depends on where the terminal is); the command is given as a `!` command or wrapped; no command is printed; or the answer later contradicts or retracts this.
