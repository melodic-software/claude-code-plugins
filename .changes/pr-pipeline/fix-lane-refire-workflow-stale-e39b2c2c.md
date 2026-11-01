---
bump: patch
---

### Fixed

- A work-resolve-issue run that waited in its slot past a lane workflow change and stopped at `Stop on stale workflow files` is re-fired at once by its own `report-outcome` (`dimension-skip: workflow-stale`, read from the jobs listing by the new `resolve-issue-stale` job), instead of waiting up to an hour for work-unblock's sweep. It posts work-unblock's re-fire record and moves `agent-ready` as the App, and backs off to the sweep after `limits.limit-stops-per-issue` re-fires since a person last added `agent-ready` or a run last reported.
- The read runner's `issue-fields` job no longer errors on a missing `log-api-budget` action when it checked out no `.base`.
