---
bump: minor
---

### Added

- The stills renderer reports each narrated moment held in silence more than 3 seconds past its
  paragraph, because its frames need longer to read: a `SILENT:` line and a `silent_holds` entry
  in `manifest.json`. It is a report, not a defect; the exit code is unchanged.
