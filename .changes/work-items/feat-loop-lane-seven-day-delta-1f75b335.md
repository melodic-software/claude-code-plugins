---
bump: minor
---

### Added

- The loop telemetry `usage_sample` records `seven_day_delta_pct` beside `five_hour_delta_pct`, derived the same way from `seven_day_pct` (null on a missing reading on either side, a first cycle, or a rollover), so a lane keeps a usage-rate measure on an account that reports no five-hour window. Measure-only, as before: no decision or threshold reads it. Follows loop-lane convention 13.0.0.
