---
bump: minor
---

### Added

- `limits.stale-queued-minutes` (default 60). A work-unblock sweep leaves a work-resolve-issue run still at status `queued` this many minutes after it was created out of the unfinished runs that `limits.refire-queue-per-slot` counts, and logs how many it left out. Such a run never got a runner, so GitHub lost it and it will never start; counted, outage-lost runs held the kill-switch re-fire room at 0 and the issue lane idle. The in-flight check for a reopened fix issue still counts every unfinished run.
