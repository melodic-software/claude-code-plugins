---
bump: patch
---

### Changed

- The Windows check catalog's Claude Code temp root entry keeps its base order and the rule that every candidate ends in `claude`, and points at the `CLAUDE_CODE_TMPDIR` row of the environment variables reference instead of stating what Claude Code appends. The environment and PATH health entry's 2047 User Path `CRIT` threshold now names its source, with an as-of date and a recheck trigger. No behavior change.
