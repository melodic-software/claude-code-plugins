---
bump: patch
---

### Fixed

- The verdict gate reader (`babysit_verify_evidence.py`) no longer falls back to listing every artifact when GitHub has deleted carried artifacts before their `expires_at`. When the incremental listing holds more than GitHub's live count, it reads again only the pages around the carried entries that expire within `EARLY_DELETION_LEAD` and lets them decide those ids, keeping the exact-count check. On the carried listing behind the `verify:unreadable` refusal of #11903, the reader now finishes incrementally in 21 page reads and 15.9 s, where it refused after 28 page reads and 64.6 s under verify-cap's 120 s limit. Each `babysit-listing-miss` line now also reports `region_pages`.
