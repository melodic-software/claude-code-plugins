---
bump: patch
---

### Fixed

- `plugin-eval`'s `run-validity.py` now reads a denied Bash call's target from the absolute arguments of its command, so a with-arm Bash denial on a path outside the plugin, such as `cat /proc/sys/kernel/yama/ptrace_scope`, is a warning when the run scores the same as its case's denial-free runs. A Bash denial on a path under or above the plugin, with no absolute argument, or whose command does not parse stays a FAIL.
