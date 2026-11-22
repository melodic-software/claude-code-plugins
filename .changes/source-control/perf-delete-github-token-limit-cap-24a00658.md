---
bump: patch
---

### Changed

- The babysit-prs rate guard's read floor is a share of the live `x-ratelimit-limit` header for every pool: GITHUB_TOKEN no longer plans to rate-limits.json's `limit-cap` of 1,000, and `BABYSIT_READ_FLOOR_HEADER_LIMIT` is gone.
