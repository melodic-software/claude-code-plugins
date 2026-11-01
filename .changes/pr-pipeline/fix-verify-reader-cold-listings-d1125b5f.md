---
bump: patch
---

### Fixed

- The verdict reader's whole artifact listing refuses `verify:unreadable` after the first when its top-up holds more artifacts than GitHub's live count, or does not read, instead of paging two more. A listing that fails once it began a whole listing is noted beside the saved listing, so later readers in the same pr-merge, ci-status or dispatcher job refuse without paging again.
- The carried files (gate cursor, artifact listing, head-ref map, run cache, lane records) come from the trusted pr-merge run with the highest id, not the first one the API lists. The API orders runs by `created_at`, and on 2026-11-01 runs created between 08:00Z and 09:00Z were stamped an hour ahead. Until 10:00Z, those runs' hour-old listings were carried above later ones, and every run read that stale listing and paged two whole listings.
