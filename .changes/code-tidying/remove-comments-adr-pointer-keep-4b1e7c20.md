---
bump: minor
---

### Added

- `/code-tidying:remove-comments` keeps a one-line ADR pointer (`# See docs/adr/0042`) that names an existing decision record of the repository, restates none of its reason, and sits at a module header or a non-obvious decision line: the shipped keep list keeps it under `necessary`, and it passes the earn-its-keep test under `explanatory`. A pointer that also states the record's reason is still ordinary rationale.
