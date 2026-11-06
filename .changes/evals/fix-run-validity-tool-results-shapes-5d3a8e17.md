---
bump: patch
---

### Fixed

- `run-validity.py` now sets aside a denied Bash read of the session's own tool-results directory
  written as several read pipelines joined by `;` or `&&`, after one opening `cd` into that
  directory (relative paths then resolve against it), or after `NAME=value` assignments. A value
  with a `/` must be a path inside the directory; any other value must be a plain literal (a
  pattern, count or name), and every path it expands into is still checked. A `cd` elsewhere or
  with a flag, a relative path that escapes, an assignment to `PATH`, `IFS`, `LD_*` or another name
  that changes how the shell or a reader works, `export`, `||`, `&`, a subshell, a redirect or any
  other command still counts as a denial. An assignment to such a name or to a path outside the
  directory, even unused, now counts as a denial where it was set aside before.
