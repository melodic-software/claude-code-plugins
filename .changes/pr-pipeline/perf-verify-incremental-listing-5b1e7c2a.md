---
bump: patch
---

### Changed

- pr-merge's merge job uploads its last saved artifact listing as `pr-merge-verify-listing` (scheduled and hand-started runs, one day), and the merge job, enable-auto-merge and ci-status's merge-queue reader fetch it from the newest such run on main (`.github/scripts/pr-merge/listing-carry.mjs`), so the verdict reader lists only the artifacts uploaded since instead of every page, one GITHUB_TOKEN request each (69 pages on 2026-10-27).
