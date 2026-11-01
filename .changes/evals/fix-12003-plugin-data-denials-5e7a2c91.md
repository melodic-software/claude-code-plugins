---
bump: patch
---

### Fixed

- `run-validity.py` counts a run whose only denials are named calls other than Skill aimed under its own plugin-data directory (`<sandbox>/config/plugins/data`, where `CLAUDE_PLUGIN_DATA` points) as a warning, not a failure. The eval sandbox denies that directory to every skill that persists state, so outcome passes of such skills read INVALID whatever the case did. A denial anywhere else in the run's config directory, in another sandbox, or with no rooted path still fails.
