---
bump: patch
---

### Changed

- pr-merge's gate keeps the run's shared post-merge answer for each candidate past the two-minute unverified age, up to 30 minutes, on the same evidence the lane room keeps it on (main's head, its config commit, the demotion records and the unverified lane merges' verifying runs unchanged), and reads it again only when one of those moved or cannot be read (`postMergeShared: kept:unverified-stale`).
