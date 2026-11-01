---
bump: patch
---

### Fixed

- The verdict gate reader (`babysit_verify_evidence.py`) settles an over-count from early deletion before it falls back to a whole listing. GitHub can delete artifacts before their `expires_at`. When the incremental listing holds more than GitHub's live count, the reader first re-reads only the pages around the carried entries that expire within `EARLY_DELETION_LEAD`, and lets those pages decide the ids. It reads at most `NEAR_EXPIRY_PAGE_CAP` (24) such pages per listing. A count those pages leave unsettled, above or below the live count, goes to the single whole listing added in #11926, which refuses `verify:unreadable` when its top-up misses the count. An over-count now takes that one whole listing even when its top-up comes up short, and the refusal is noted for the job's later readers. On the carried listing behind the `verify:unreadable` refusal of #11903, the reader finished incrementally in 21 page reads and 15.9 s. With #11926 alone, that over-count goes to a whole listing of about 133 pages, past verify-cap's 120 s limit, so it refuses (derived from the measured page count, not re-run). Each `babysit-listing-miss` line also reports `region_pages`.
