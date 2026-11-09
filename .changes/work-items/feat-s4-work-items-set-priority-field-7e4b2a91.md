---
bump: minor
---

### Changed

- `/work-items:triage` and `/work-items:track add --priority` set the organization `Priority` issue field, and use the repository's `priority:` labels where there is no such field or the adapter cannot write one.
