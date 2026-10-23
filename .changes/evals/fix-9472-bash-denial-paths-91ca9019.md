---
bump: patch
---

### Fixed

- `plugin-eval`'s `run-validity.py` now reads a denied Bash call's target from the absolute paths in its command, so a with-arm Bash denial on a path outside the plugin, such as `cat /proc/sys/kernel/yama/ptrace_scope`, is a warning when the run scores the same as its case's denial-free runs. A Bash denial stays a FAIL when any of its paths is under or above the plugin, or when its command does not parse, has no absolute path, or holds anything the check cannot resolve: a word the shell expands (`$`, a backtick, a glob, a leading `~`), any relative word after the command word other than a flag (so `cat SKILL.md /proc/version` and `grep foo /proc/x` both stay a FAIL), a path packed after another character (`/a:/b`, `/a,/b`), or a `/proc/self`, `/proc/thread-self` or `/dev/fd` path, in any spelling that normalizes to one. A denied path holding a NUL byte is now a FAIL with a verdict instead of a traceback.
