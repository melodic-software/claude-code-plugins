---
bump: patch
---

### Changed

- The shared `lib/publish-gate.mjs` copy gains the lanes' leak-scan functions (`scanLeak`, `deeperLeak`, `changedBytes`). Nothing in this plugin calls them, and its publish gate behaves as before.
