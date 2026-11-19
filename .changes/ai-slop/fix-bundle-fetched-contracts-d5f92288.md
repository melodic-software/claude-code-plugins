---
bump: patch
---

### Fixed

- `/ai-slop:audit` reads the detector-findings contract from the copy bundled at
  `reference/detector-findings.md` before writing a findings file, instead of fetching it from the
  publisher's repository, so persisting works offline.
