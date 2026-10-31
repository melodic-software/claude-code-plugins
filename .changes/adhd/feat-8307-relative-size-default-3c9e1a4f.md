---
bump: minor
---

### Changed

- `/adhd:shape` rule 6 sizes work as Small, Medium or Large, with what makes it that size, instead of estimating time. It states minutes, hours, days or weeks only when the new `time_units` option is on, and keeps a time budget the reader states in the reader's words.

### Added

- `time_units` `userConfig` option (boolean, default off) that turns time units back on in `/adhd:shape` estimates.
- The `sh-estimate-and-list-cap` eval grades a relative size and no time units, in place of a concrete time estimate.
