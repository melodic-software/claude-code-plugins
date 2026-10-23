---
bump: patch
---

### Fixed

- `plugin-eval`'s `run-validity.py` now reads a denied Bash call's target from the absolute paths in its command, so a with-arm Bash denial on a path outside the plugin, such as `cat /proc/sys/kernel/yama/ptrace_scope`, is a warning when the run scores the same as its case's denial-free runs. A Bash denial stays a FAIL when any of its paths is under or above the plugin, or when its command does not parse, has no absolute path, or holds anything the check cannot resolve: a word the shell expands (`$`, a backtick, a glob, a leading `~`), `..` or a relative path with a slash, a path packed after another character (`/a:/b`, `/a,/b`), `/proc/self` or `/dev/fd`, a backslash, or `cd`, `pushd` or `popd`. A denied path holding a NUL byte is now a FAIL with a verdict instead of a traceback.
