---
bump: patch
---

### Changed

- `babysit_verify_evidence.py` lists only the newest artifact pages on top of a whole listing begun within three hours: its own, the run's saved one, or the one a trusted pr-merge run carried (`BABYSIT_VERIFY_LISTING_CARRY`). It reads pages newest id first down past that listing's highest id until an artifact created two hours before that listing was read, drops entries expired by the first page's `Date` or missing from the pages it read, and keeps the result only when it holds exactly the first page's live `total_count`. Any other count, a missing, older or malformed base, or a failed read lists every page as before. On 2026-10-27 this read 2 pages in 1.3 s where the full listing read 69 pages in about 51 s, with the same artifacts.
