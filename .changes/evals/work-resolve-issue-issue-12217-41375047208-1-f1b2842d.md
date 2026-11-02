---
bump: patch
---

### Fixed

- `run-validity.py` now sets aside a denied Bash read of the session's own tool-results directory, as it already did for `Read`, `Grep` and `Glob`. The command must be a pipeline of `cat`, `head`, `wc`, `grep` or `sed -n` whose every path is under that directory. A redirect, another command or operator, an unquoted glob, brace or `$`, or a path outside it still counts as a denial.
