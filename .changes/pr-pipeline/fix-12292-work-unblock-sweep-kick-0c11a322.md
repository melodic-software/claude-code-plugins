---
bump: patch
---

### Fixed

- work-unblock no longer runs its sweep when a listed human closes the issue labeled `work-unblock-sweep`: that close now runs the close path like any other, and the sweep runs only on its hourly schedule and after a work-resolve-issue run, so the next of those is the probe after an outage or a kill switch. The `sweep-kick` notice is gone. The `label-unblocked` job also drops `queue: max` and keeps GitHub's default of one waiting run, which a newer run replaces: the next sweep repeats a replaced run's work.
