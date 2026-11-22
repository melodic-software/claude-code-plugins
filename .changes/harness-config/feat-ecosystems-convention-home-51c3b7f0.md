---
bump: patch
---

### Changed

- The automation-gaps rule inventory reads ecosystem records from `docs/conventions/ecosystems/` and a legacy `.claude/ecosystems/` record of a name not there; a legacy record shadowed by one of the same name is named with the file that takes its place.
