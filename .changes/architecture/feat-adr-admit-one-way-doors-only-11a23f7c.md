---
bump: minor
---

### Changed

- `/architecture:adr`'s admission test now requires all three parts: a real alternative was weighed, the decision is a one-way door by the shared definition (or matches an `adr_extra_triggers` entry), and its reason is not visible in the code. A two-way door never earns a record, however surprising; its reason belongs beside the code or setting, or in the pull request. `audit` checks records against the same three parts.
- `adr_extra_triggers` entries now name decisions the team treats as one-way doors; they no longer stand in for the other two parts.

### Added

- The plugin carries the shared one-way and two-way door definition at `reference/one-way-doors.md`, generated from `lib/one-way-doors.md`.
