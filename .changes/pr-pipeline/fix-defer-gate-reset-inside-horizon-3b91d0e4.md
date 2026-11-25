---
bump: patch
---

### Fixed

- The kill-switch gate's projection (`defer-project` and `start-project`) no longer stops a run whose horizon reaches past the window's reset: that run ends in the next window, so it stops only when the window is projected to run out before the reset. Before, a review read 112 s before the reset, with 0.24 of the limit projected left there, deferred against `defer-project` 0.3, turning `CI Status` red until a manual re-run. The notice names which rule decided.
