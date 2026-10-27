---
bump: patch
---

### Changed

- `babysit_verify_evidence.py` lists only the newest artifact pages on top of a whole listing begun within three hours: its own, the run's saved one, or the one a trusted pr-merge run carried (`BABYSIT_VERIFY_LISTING_CARRY`). It reads pages newest id first down past that listing's highest id until an artifact created two hours before that listing was read, drops entries expired by the first page's `Date` or missing from the pages it read, and keeps the result only when it holds exactly the first page's live `total_count`. Any other count, a missing, older or malformed base, or a failed read lists every page as before. On 2026-10-27 this read 2 pages in 1.3 to 1.6 s where the full listing read 69 pages in 50 to 58 s, and held every artifact the full listing held plus those the full listing skipped at its page boundaries.

### Fixed

- `babysit_verify_evidence.py` no longer judges on a whole artifact listing that skipped an artifact at a page boundary. A whole listing can skip one when an earlier artifact expires while it pages: on 2026-10-27 two of three whole listings skipped live artifacts, FAIL verdicts among them, so a pull request could be allowed past a FAIL. Each whole listing is now deduplicated by id, added to the ones read before it, and kept only when a top-up from the first page shows it holds GitHub's live `total_count`; after three whole listings that never hold it the pull request refuses `verify:unreadable`.
