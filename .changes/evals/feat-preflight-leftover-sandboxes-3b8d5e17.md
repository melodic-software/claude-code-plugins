---
bump: minor
---

### Added

- `plugin-eval` preflight now reports `leftover_sandboxes` (count and size of `claude-eval-*` directories in the temp directory) and `tmp_free`, and prints the cleanup commands when any are left. Preflight removes nothing and does not block the run on either field.
