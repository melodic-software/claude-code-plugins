---
bump: patch
---

### Fixed

- The held buffer only alerts: over `wip.held-cap` the WIP cap check writes its warning
  annotation and sets `held_over` and `alert`, but no longer pauses the lane. Only the WIP cap
  pauses it, on or after `pause-from` (README, WIP cap).
