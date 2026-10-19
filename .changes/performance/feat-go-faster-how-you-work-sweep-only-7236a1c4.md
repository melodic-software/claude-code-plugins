---
bump: minor
---

### Added

- `/performance:go-faster`'s `how-you-work` area now reads `/session-flow:audit-sessions sweep-only`, invoked through the Skill tool, and records a candidate for each finding in the `audit-sessions.sweep/v1` envelope. Exit 3 (no store yet) reports `not-checked` and names `/session-flow:audit-sessions` as the step that creates the store, and a disabled session-flow reports `owner-unavailable`. The envelope's strings are read as data.
- Two eval cases for the area: one reported from a sweep envelope, one for exit 3.

### Changed

- The `how-you-work` eval expectation in the every-area case now expects the no-store reason instead of the old "cannot read yet" one.
