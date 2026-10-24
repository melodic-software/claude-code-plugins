---
bump: minor
---

### Changed

- The monthly checkup runs in auto mode: the Task Scheduler wrapper is a static copy that starts `claude -p` with a 90-minute limit, without the exact allow rules or the deny settings file. Rerun `/machine-health:setup schedule` to replace an installed copy.
- The Desktop scheduled task offers Auto mode only.

### Added

- A scheduled run researches up to five findings that are new since the previous run through `/discovery:research`, writes the notes to `discovery-<runStamp>.md` beside the report, and grounds its TODO.md check proposals with sources.

### Removed

- The legacy TODO.md-to-approvals migration: approvals come only from `/machine-health:setup`.
