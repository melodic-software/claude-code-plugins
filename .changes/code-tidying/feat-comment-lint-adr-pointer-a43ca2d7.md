---
bump: minor
---

### Added

- The comment lint passes an ADR pointer under the `necessary` posture: a one-line comment holding only a record id (`ADR-0042`, `ADR 42`) or one relative path into `docs/adr/`, optionally after `See`, when that record exists. A pointer to a missing record, or one that also states a reason, still fails.

### Changed

- `/code-tidying:audit-dead-code` adjudicates a candidate that a decision record names by symbol or file path as `uncertain`, citing the record, never `dead`.
