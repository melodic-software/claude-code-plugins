---
bump: patch
---

### Fixed

- **`babysit-prs` verdict reader stops at the read floor when ci-status runs it.** With `BABYSIT_READ_FLOOR_STOP=1`, which ci-status sets on its merge-queue judgment, `babysit_gh` sends no read (any call or page) once its pool is below its `read-floor` share, and the judgment fails closed. ci-status no longer prices an index-mode judgment from the unfiltered artifact listing, which was returning HTTP 500 and holding every cold merge-queue entry.
