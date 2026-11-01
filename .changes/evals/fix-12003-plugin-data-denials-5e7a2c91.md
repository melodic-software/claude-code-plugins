---
bump: patch
---

### Fixed

- `run-validity.py` treats a denied named call other than Skill whose every target path is under the run's own plugin-data directory (`<sandbox>/config/plugins/data`, where `CLAUDE_PLUGIN_DATA` points) as environment: a warning that never counts toward a failure. The eval sandbox denies that directory to every skill that persists state, so outcome passes of such skills read INVALID whatever the case did. A run with other denials is judged on those alone, and its FAIL reason counts only them. A denial anywhere else in the run's config directory, in another sandbox, or with no rooted path still fails.
