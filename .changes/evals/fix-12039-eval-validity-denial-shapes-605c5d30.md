---
bump: patch
---

### Fixed

- `run-validity.py` treats a denied `Read`, `Grep` or `Glob` whose every target path is under the session's own `<sandbox>/config/projects/*/*/tool-results/` as environment: a warning that never counts toward a failure, counted apart in the summary. Claude Code saves a large tool result there and the model reads it back, and the run's config directory is denied, so long outputs made outcome passes read INVALID whatever the case did. A Bash call, a write, another path in the config directory (user `settings.json` included), or another sandbox's results still fail.

### Changed

- The case-authoring checklist says a case whose skill must write under the workspace's `.claude/` cannot be measured past that write, and that a settings case seeds its settings in the workspace; the Denials section of reading-results lists both set-aside denial kinds.
