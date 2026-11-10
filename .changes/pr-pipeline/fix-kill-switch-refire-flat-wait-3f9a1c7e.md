---
bump: minor
---

### Added

- `limits.refire-queue-per-slot` (default 2). A work-unblock sweep re-fires issues the lanes kill switch stranded, oldest refused run first, only until the unfinished work-resolve-issue runs reach this value times the lane's `SLOTS` (read from `work-resolve-issue.yml`), and never more than `limits.restarts-per-run`. After the switch clears, the lane stays full with a short queue, and each finished run's sweep tops that queue back up.

### Fixed

- work-unblock re-fires an issue the lanes kill switch stopped on a flat wait once it is past `limits.limit-stops-per-issue` trips. The wait is the `limits.stranded-backoff-hours` `kill-switch` value (1 hour here), counted from when the refused run ended. Before, the wait doubled per trip up to 24 hours. Trips below that bound keep their waits, and kill-switch trips still never count toward a give-up. The other causes still double.
