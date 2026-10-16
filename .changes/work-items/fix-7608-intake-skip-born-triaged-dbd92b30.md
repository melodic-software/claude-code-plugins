---
bump: patch
---

### Fixed

- `decompose` item bodies end with the `<!-- work-items:born-triaged -->` marker, so intake
  automation can skip items published already triaged instead of re-triaging them (#7608).
