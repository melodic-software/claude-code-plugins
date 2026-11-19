---
bump: patch
---

### Fixed

- `/harness-config:audit-instructions --persist-findings` reads the detector-findings contract from
  the copy bundled at `reference/detector-findings.md` instead of fetching it from the publisher's
  repository, so persisting works offline.
