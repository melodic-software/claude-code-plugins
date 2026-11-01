---
bump: patch
---

### Fixed

- The verdict gate reader (`babysit_verify_evidence.py`) settles an over-count from early deletion
  before it falls back to a whole listing. GitHub can delete artifacts before their `expires_at`.
  When the incremental listing or a whole listing's top-up holds more than GitHub's live count, the
  reader first re-reads only the pages around the carried entries that expire within
  `EARLY_DELETION_LEAD`. Those pages add every id they hold. An id inside their span that they omit
  is dropped only when its own read answers 404 or shows it expired, because pages read one at a
  time can skip a live entry at a boundary when an artifact above it is deleted. The re-read takes
  at most `NEAR_EXPIRY_PAGE_CAP` (24) pages and `NEAR_EXPIRY_ID_READ_CAP` (34) id reads per listing.
  A count it leaves unsettled, or an id read with any other answer, goes to the single whole listing
  added in #11926, which refuses `verify:unreadable` when its top-up misses the count. An id read
  that answers a 5xx is read again after each of `LISTING_WAITS`, as a page is; one still failing
  then fails the read as transient, so a top-up refuses without noting a failed listing for the job.
- An over-count now takes that whole listing at most once a job, even when its top-up comes up
  short. Once that listing starts paging, it is noted beside the saved listing
  (`.overcount-fallback`) with its outcome. A later reader in the job whose pages over-count then
  refuses without another whole listing, keeping the caller-limit prefix when that listing ran out
  of a caller's time. A refusal before paging leaves the listing to the next reader.
- On the carried listing behind the `verify:unreadable` refusal of #11903, the re-read finished
  incrementally in 21 page reads and 15.9 s, measured before the per-id reads were added. With
  #11926 alone, that over-count goes to a whole listing of about 133 pages, past verify-cap's 120 s
  limit, so it refuses (derived from the measured page count, not re-run). Each
  `babysit-listing-miss` line also reports `region_pages`.
