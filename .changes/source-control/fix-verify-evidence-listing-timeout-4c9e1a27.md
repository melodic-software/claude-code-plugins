---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` reads GitHub's live artifact `total_count` from one page before its
  whole listings and sizes their shared timeout from it: each whole listing and its 7-page top-up at
  1 s a page, at most 300 s (`LISTING_TIMEOUT_SECONDS`). A count past 293 pages, which no whole
  listing reads in time, refuses `verify:unreadable` before paging, with the count and the cap in
  the detail, instead of running into a caller's timeout with no reason.
