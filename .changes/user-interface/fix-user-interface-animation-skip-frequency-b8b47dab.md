---
bump: patch
---

### Fixed

- The should-it-animate frequency gate now reads `animation.skip_frequency` at every site that states it (`reference/animation/catalog.md`, `/user-interface:write-animation` step 2 and the audit motion lane's severity list), in uses per day, in place of a fixed number or "many times an hour", so changing the setting changes the gate.
