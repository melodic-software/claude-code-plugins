---
bump: patch
---

### Added

- The bundled publish gate (`lib/publish-gate.mjs`) gains `locateHit` and `hitFingerprint`: for a blocked leak-scan hit, the rule, the path and the line number, with no character of the match and every character outside printable ASCII escaped. `scanLeak` is unchanged.
