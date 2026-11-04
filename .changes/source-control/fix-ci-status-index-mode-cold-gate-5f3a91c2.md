---
bump: patch
---

### Fixed

- **`babysit-prs` verdict reader stops at the read floor when ci-status runs it.** With `BABYSIT_VERIFY_FLOOR_STOP=1`, which ci-status sets on its merge-queue judgment, the reader sends no read once a GitHub API pool it read is below its `read-floor` share, and the judgment fails closed. ci-status no longer prices an index-mode judgment from the unfiltered artifact listing, which was returning HTTP 500 and holding every cold merge-queue entry.
