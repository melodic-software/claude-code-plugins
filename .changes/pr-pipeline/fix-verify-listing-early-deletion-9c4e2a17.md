---
bump: patch
---

### Fixed

- The verdict reader's carried listing first re-reads the pages around entries near expiry, up to a page cap, when it holds more than GitHub's live count. That over-count then takes at most one whole listing a job.
- The merge queue's cold-read headroom check (`cold_cost` in pr-require-checks.yml) counts those re-read pages, up to 24 more requests a cold read: 1,647 at 7,522 artifacts and 264 FAILs.
