---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py` reads GitHub's live artifact `total_count` from one page before its
  whole listings and sizes their shared timeout from it: each whole listing and its 7-page top-up at
  1 s a page, at most 300 s (`LISTING_TIMEOUT_SECONDS`), or less when the caller names the limit it
  kills the reader at in `BABYSIT_VERIFY_DEADLINE_SECONDS` (and itself in `BABYSIT_VERIFY_CALLER`),
  less 15 s for the reads after the listing. A whole listing that cannot fit refuses
  `verify:unreadable` before paging, with the pages, the seconds they need and the budget (and the
  caller) in the detail, instead of being killed with no reason. That detail starts with
  `DEADLINE_UNREADABLE` when the caller's limit, not the 300 s cap, is what it does not fit in. The
  caller's limit bounds the count read too, and the whole listings' timeout is at least gh's 60 s
  per-call default unless the cap or that limit leaves less.
