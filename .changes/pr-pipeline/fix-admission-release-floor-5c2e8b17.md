---
bump: minor
---

### Added

- `limits.admission-min-per-hour` (default 1, 0 to 100): the issue lane's queued cap never falls
  below this rate times `wip.target-lead-time-hours`, so a day with no lane merges cannot hold
  admissions shut. 0 removes the floor.
