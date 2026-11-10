---
bump: minor
---

### Added

- `repo-sweep` hygiene catalog: a read-only `adr-audit` step runs `/architecture:record-decision audit` where the repository has an ADR folder. Retirements go through `/architecture:record-decision` in their own change, after a yes.
