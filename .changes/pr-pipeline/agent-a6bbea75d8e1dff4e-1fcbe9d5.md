---
bump: patch
---

### Fixed

- A failed `pr-unblock / resolve-conflicts` run no longer marks its head handled for good: the dispatcher retries it until `limits.limit-stops-per-head` failures (limit stops included) stand on the head.
- A resolve-conflicts run skipped while the pull request was held (`Skipped: awaiting-human`) no longer marks its head handled: the dispatcher skips a held pull request itself, without recording it, and the next sweep after the hold comes off dispatches it. The dispatch record's version is now 4, so heads recorded under the old rule are read again.
