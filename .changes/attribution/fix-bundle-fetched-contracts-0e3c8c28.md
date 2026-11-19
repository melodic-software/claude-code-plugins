---
bump: patch
---

### Fixed

- `/attribution:audit`'s second rung for the detector-findings contract is the copy bundled at
  `reference/detector-findings.md` instead of the publisher's raw URL, so a run without the
  `review` plugin still persists findings offline.
