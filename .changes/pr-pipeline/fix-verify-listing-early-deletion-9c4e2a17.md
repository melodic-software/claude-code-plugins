---
bump: patch
---

### Fixed

- The verdict reader's carried listing first re-reads the pages around entries near expiry when it holds more than GitHub's live count. That re-read has a page cap and an id-read cap, and drops an omitted entry only on a 404. The over-count then takes at most one whole listing a job.
- The merge queue's cold-read headroom check (`cold_cost` in pr-require-checks.yml) now counts those reads, up to 58 more requests a cold read: 1,681 at 7,522 artifacts and 264 FAILs.
