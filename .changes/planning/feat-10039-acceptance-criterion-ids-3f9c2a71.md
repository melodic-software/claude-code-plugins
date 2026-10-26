---
bump: minor
---

### Added

- `check-plan-outcome.sh` grades a new `criteria` criterion: each acceptance criterion id (`AC1:`) must be named on some phase's `**Satisfies:**` line. It fails an unmapped id (`unmapped=`), an id no criterion defines (`unknown=`), a criterion without an id beside ones with ids, and an id used twice. A plan whose criteria carry no id passes with a warning.

### Changed

- `/planning:interview` writes each Brief acceptance criterion with an id, `- AC<n>: <criterion>`, with an EARS tag after the id under the `ears` format.
- `/planning:plan` numbers any Brief criteria that lack ids, gives a criterion it adds the next id, and has each phase name the ids it satisfies; its outcome gate maps them by script instead of by reading.
