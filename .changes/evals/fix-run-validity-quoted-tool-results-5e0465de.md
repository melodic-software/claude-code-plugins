---
bump: patch
---

### Fixed

- `run-validity.py`'s `session started` check no longer fails a run whose failed Bash call only reads, such as a grep of a saved tool result, when its output quotes a read-only file system line it read; a call that writes still fails the run (#12422).
- `run-validity.py`'s `permission denials` check sets aside a denied Bash read of the session's own tool results that names the file through an opening `NAME=value` command, as in `F=<saved>; grep -n x "$F"` (#12422).
