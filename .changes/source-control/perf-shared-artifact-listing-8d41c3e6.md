---
bump: patch
---

### Changed

- The pr-merge gate judges its own candidate's verifier verdict `provisional` (`babysit_verify_evidence.py` `Reader.evidence(..., provisional=True)`) on the run's saved artifact listing at any age instead of listing again once that listing is two minutes old. An allow there still lists again before the gate allows the candidate, as before; a refusal no later upload clears (`STANDING`: a FAIL at the head, the FAIL cap, an old pull request) stands on it; any other refusal is judged again on a listing under two minutes old, so it never dequeues an entry on an older one. Queued entries are judged as before. A candidate whose verdict allows and that the gate then refuses for anything else, such as its risk score, no longer lists at all. In a fixture shaped like 2026-10-27's repository the merge job's listings fell from 4 to 3 (17 candidates in about 6 minutes) and from 4 to 2 (6 candidates two minutes apart) with an empty merge queue, and stay the same with a queued entry, whose keep needs a recent listing.

### Fixed

- `babysit_verify_evidence.py` reads the incremental listing a second time on the same base before it pages the whole listing (`INCREMENTAL_READS`), only when its pages read whole but missed the live count; a failed read (a timeout, a 429 or a rate-limit 403 included) pages the whole listing at once, as before. The first pr-merge tick on a carried base (run 40600822658, 2026-10-27) read 4 pages that missed the live count (cause unverified) and then paged all 71 in the skip filter; the same base read again five minutes later held the live count in 4 pages.
