---
bump: minor
---

### Added

- `target` ranks slow checks (git hooks, local check scripts, CI jobs): one candidate per check and lane, a p50 and p90 baseline per lane, the moves to rank (scope to the change, move to a later lane, run in parallel with every job's failure reported, the tool's cache or incremental mode, a tool swap), a dependency-collision check on any upgrade or swap, stack specifics resolved at run time, and growing check counts routed to `/toolchain:ratchet`. A new eval case, `ta-check-lanes-per-stage`, covers it.
- `goal` records `50,90` as the percentile list for a check-lane goal.
