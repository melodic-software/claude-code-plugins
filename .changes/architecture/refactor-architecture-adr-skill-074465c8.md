---
bump: major
---

### Changed

- The decision-record skill is invoked as `/architecture:adr`, with no alias, and splits into three actions: `record` (the default, the recording flow), `audit` (read-only) and `prune`.
- The citation sweep lists a hit that does not refer to the record, such as a database migration `0007_...` in another numbered series, as not a citation and edits nothing.
- `## Next` names each follow-up with the outcome it applies to.

### Added

- `/architecture:adr prune` runs the audit, presents its candidates one group at a time, and retires only the records you accept, through the `adr_retirement` setting, the git-history pointer line and the citation sweep. `audit` no longer offers retirement itself.
