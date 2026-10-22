---
bump: minor
---

### Added

- implement reads paved-path entries before editing

  /implementation:implement now resolves the standards index before its
  first edit and, when it has a paved-path row, reads only the entries for the
  concerns the paths it edits touch. A plan's per-phase criteria still win.
  With no row it does nothing extra.
