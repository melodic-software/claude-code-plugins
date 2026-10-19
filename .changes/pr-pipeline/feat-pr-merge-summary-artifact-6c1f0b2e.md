---
bump: minor
---

### Added

- The pr-merge workflow's merge job uploads each sweep's verdicts as the `pr-merge-summary` artifact
  (30-day retention): the run, the candidate, enqueued, merged and held counts, refusal counts by
  reason with PR numbers and run lists stripped so they aggregate, any gate-budget stop, and the
  per-candidate results. It also logs one `refusal-counts=` line built from that data, so a log
  search finds it once.

### Fixed

- The `log-api-budget` action no longer reports a token's cost as `window-rolled` when the reset
  time moved earlier within one window; it counts `used` at end minus `used` at start, and calls
  the window rolled only when `used` fell or the reset moved more than 10 minutes later.
