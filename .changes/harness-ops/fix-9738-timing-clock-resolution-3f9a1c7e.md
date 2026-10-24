---
bump: patch
---

### Fixed

- The `/harness-ops:plugins` sync report's Timing rows now end `; clock resolution: microseconds` (or `nanoseconds`, `seconds`) instead of appending `(microseconds)` after a seconds value, which read as the unit of the figures.
