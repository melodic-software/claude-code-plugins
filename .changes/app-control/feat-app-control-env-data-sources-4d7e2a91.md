---
bump: minor
---

### Added

- Each environment entry in a control skill's committed config may list its data sources (logs,
  telemetry, database, tracker, error reporter), each with where to read it and a read level of
  `never`, `attended` or `unattended`. `/app-control:drive ready` reports each environment's
  sources and the kinds it is missing, reading none of them; `/app-control:map` create asks the
  read levels and refresh adds a missing or moved source at `never`.
- Every `/app-control:drive` report lists the lessons the run learned about driving the app, as
  `/app-control:map refresh "<lesson>"` lines, in a new `lessons` field.

### Changed

- `/app-control:drive` performs a feature's `## Reset` on a reused instance only when the hub's
  `Data:` line names a per-run data directory; with `Data: none:` it stops that instance and
  launches fresh, or blocks with the reason where it cannot.

- `/app-control:map` is the only writer of a control skill's Gotchas, and refresh accepts lessons
  handed in from `/app-control:drive` and `/debugging:debug` reports as well as
  `/verification:confirm`.
