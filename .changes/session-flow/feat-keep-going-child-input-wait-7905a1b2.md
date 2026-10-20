---
bump: minor
---

### Added

- `/session-flow:keep-going` lists the child process tree of each background shell and flags any child waiting on an interactive prompt or stdin, using the new `check-child-input-wait.py` (Linux through `/proc`, macOS through `ps`, Windows through PowerShell). A process the platform gives no signal for reports `unknown`, never "not waiting". Killing a flagged child stays behind the side-effect gate.
- The shared off-thread reference lists "external CLI processes and their child trees" as a kind.
