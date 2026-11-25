---
bump: patch
---

### Fixed

- The kill-switch gate's projection (`defer-project` and `start-project`) scales its share for a run whose horizon reaches past the window's reset: only the part of the run before the reset draws on this window, so the gate stops while the share projected left at the reset is under the share x seconds to the reset / horizon seconds. Before, a review read 112 s before the reset, with 0.24 of the limit projected left there, deferred against the full `defer-project` 0.3 (its scaled floor is 0.07), turning `CI Status` red until a manual re-run. The notice names the scaled floor.
