---
bump: patch
---

### Fixed

- `run-validity.py` no longer fails the row count on a `history_file` case that ran single-arm by
  design: a case whose case.yaml sets `context.history_file` and whose result records no
  without-arm key is reported as a single-arm warning with no delta. An empty or short without-arm
  still fails.
- `run-validity.py` drops a Bash redirect that names no file (`2>&1`, `2>/dev/null`, `>/dev/null`)
  before reading a command's paths, so a denied `ls <plugin-data> 2>&1` falls under the
  plugin-data warning instead of counting as a cwd-relative path and a FAIL.
