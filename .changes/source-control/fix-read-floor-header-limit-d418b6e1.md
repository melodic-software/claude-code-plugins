---
bump: patch
---

### Fixed

- `BABYSIT_READ_FLOOR_HEADER_LIMIT=1` makes `babysit_gh`'s read floor a share of the header's rate limit rather than the pool's `limit-cap`; ci-status's merge-group verdict reader sets it (owner decision D418).
