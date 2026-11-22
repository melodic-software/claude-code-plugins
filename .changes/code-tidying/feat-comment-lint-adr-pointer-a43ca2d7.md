---
bump: minor
---

### Added

- The comment lint passes an ADR pointer under the `necessary` posture: a one-line comment holding only a record id (`ADR-0042`, `ADR 42`) or one relative path into the decision-record folder, optionally after `See`, when that record exists in the snapshot the lint reads the file from (the index, the work tree with `--worktree`, or the pushed tips). A pointer to a missing record, or one that also states a reason, still fails. The new team-file setting `comment_adr_dir` names that folder (default `docs/adr`); a value outside the repository is ignored and the default applies.

### Changed

- `/code-tidying:audit-dead-code` adjudicates a candidate that a decision record names by symbol or file path as `uncertain`, citing the record, never `dead`.
