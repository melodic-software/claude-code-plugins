---
bump: patch
---

### Changed

- An approval no longer carries across a push that touches `plugins/testing/scripts/**` or `plugins/testing/skills/run-e2e/scripts/**` (`CARRY_REFUSES`), since `maintenance-verify-whole-map.yml`, a hold path, runs the map settings resolve and the findings checker from there.
