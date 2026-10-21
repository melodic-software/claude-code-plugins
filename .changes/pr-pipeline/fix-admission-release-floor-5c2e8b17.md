---
bump: minor
---

### Added

- `limits.admission-min-per-hour` (default 1, 0 to 100): the admission release point never falls
  below this rate times `admission-window-hours`. Before it, a day with no lane merges set the
  release point to 0, so `admission-window.mjs` held admissions, no lane PR opened, and merges
  stayed at 0. 0 removes the floor.
