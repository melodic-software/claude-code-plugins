---
bump: patch
---

### Changed

- `babysit_verify_evidence.py` reads an incremental artifact listing that missed GitHub's live `total_count` up to three times on the same base, waiting 15 s and then 30 s between reads (`INCREMENTAL_WAITS`), inside one `LISTING_TIMEOUT_SECONDS`, before it pages the whole listing. Scheduled pr-merge run 40726697038 (2026-10-28) read two incremental listings back to back, both missed, and its skip step then made 218 GITHUB_TOKEN requests over 2.5 minutes (207 whole-listing pages at about 0.7 s a page), against 4 in the next run. In run 40600822658 (2026-10-27), a base whose first read missed held the count when read again five minutes later. Of 239 merge runs that week, 60 made over 150 GITHUB_TOKEN requests (median 80). A listing is still kept only when it holds exactly the live count, a persistent miss still pages the whole listing, and a failed read still pages it at once.
- Each read that misses the live count prints one `babysit-listing-miss` JSON line on stderr: the stage (`incremental`, or a whole listing's `top-up`), the listed and live counts, the fresh and carried entries, the pages read, and the base's age. Stdout and every decision are unchanged.
