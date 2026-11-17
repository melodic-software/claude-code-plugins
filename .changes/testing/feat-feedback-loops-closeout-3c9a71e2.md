---
bump: minor
---

### Added

- `/testing:diagnose` reads each environment's data sources through `/app-control:drive ready`
  when the failing test drives a running app, each source only at its read level.
