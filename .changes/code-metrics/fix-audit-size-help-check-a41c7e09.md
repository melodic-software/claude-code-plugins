---
bump: patch
---

### Fixed

- `audit-size.sh --help` lists `--check`, says what each `size.check` rule fails, and gives the
  exit codes under `--check`. The help text now lives in the script as a string rather than its
  header comment.
