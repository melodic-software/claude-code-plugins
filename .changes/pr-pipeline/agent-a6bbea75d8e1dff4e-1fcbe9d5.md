---
bump: patch
---

### Fixed

- A failed `pr-unblock / resolve-conflicts` run no longer marks its head handled for good: the dispatcher retries it until `limits.limit-stops-per-head` failures (limit stops included) stand on the head.
- A resolve-conflicts run skipped while the pull request was held (`Skipped: awaiting-human`) no longer marks its head handled: the dispatcher skips a held pull request itself, without recording it, and the next sweep after the hold comes off dispatches it. The dispatch record's version is now 4, so heads recorded under the old rule are read again.
- fix-ci no longer leaves a head for good after a run that found no failing check (`not-applicable`) or `fix-ci-restarts` failed runs: once the base tip moves past those runs the dispatcher dispatches the head again, until `limits.limit-stops-per-head` such runs stand on it. A new head starts with none.
