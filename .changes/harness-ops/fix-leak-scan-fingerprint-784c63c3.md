---
bump: patch
---

### Added

- The bundled publish gate (`lib/publish-gate.mjs`) gains `locateHit` and `hitFingerprint`: for a blocked leak-scan hit, the rule, path, line and the match's first 6 characters followed by a fixed mask, with none of a match shorter than 12 characters. `scanLeak` is unchanged.
