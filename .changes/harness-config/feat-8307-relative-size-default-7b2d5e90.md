---
bump: minor
---

### Changed

- `/harness-config:audit-automation-gaps` sizes each PASS or CONDITIONAL implementation plan as Small, Medium or Large instead of an effort estimate. It states minutes, hours, days or weeks only when the new `time_units` option is on, and quotes a time budget the user states in the user's words.

### Added

- `time_units` `userConfig` option (boolean, default off) that turns time units back on in `/harness-config:audit-automation-gaps` plan sizes.
