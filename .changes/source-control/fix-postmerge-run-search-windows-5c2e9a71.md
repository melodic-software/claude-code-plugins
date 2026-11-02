---
bump: patch
---

### Fixed

- The post-merge check reads its canary and full-run listings in `created` windows. Each window is read page by page, and a window whose first page reaches the 1000-run search cap is halved and read again. A one-second window still at the cap, or a listing that would pass 16 window reads, stays unreadable. A listing past 1000 runs no longer makes every check unreadable, and every window keeps the `total_count` completeness check.
- A window's pages are read while the last one is full, never stopped at the `total_count` a page claims, and the runs must equal that count, in the post-merge check and in `babysit_verify_evidence.py legacy-fails`. A count below the runs listed refuses instead of cutting the oldest runs off.
