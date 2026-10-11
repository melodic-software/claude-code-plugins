---
bump: minor
---

### Added

- `/work-items:ship run #N` runs one container's ready items under its recorded execution shape, attended only: it claims them after the user approves the item list, hands them to `/implementation:implement-dispatch`'s item-list mode, and lands them one at a time, onto the integration branch as checkpoints or as per-item PRs. `ship` now routes and runs one container.

### Changed

- The execution-shape reference replaces "one item in flight" with "many in flight, the runner lands one at a time": sessions working a shared branch directly still keep one item in flight, and a runner that is the only writer may keep many.
