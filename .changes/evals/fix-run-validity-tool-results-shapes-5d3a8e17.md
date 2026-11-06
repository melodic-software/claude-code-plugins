---
bump: patch
---

### Fixed

- `run-validity.py` now sets aside a denied Bash read of the session's own tool-results directory
  written as several read pipelines joined by `;` or `&&`, after one opening `cd` into that
  directory (relative paths then resolve against it), or after `NAME=<path>` assignments whose
  values lie there. A `cd` elsewhere or with a flag, a relative path that escapes, an assignment
  outside the directory or to `PATH`, `IFS`, `LD_*` or another name that changes how the shell or
  a reader works, `export`, `||`, `&`, a subshell, a redirect or any other command still counts as
  a denial. An assignment to such a name or to a path outside the directory, even unused, now
  counts as a denial where it was set aside before.
