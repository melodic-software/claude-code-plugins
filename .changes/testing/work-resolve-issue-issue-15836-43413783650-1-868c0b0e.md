---
bump: minor
---

### Added

- `/testing:diagnose`'s loop checks the shared premise after a second failed fix, before a third fix and before replanning: through `/debugging:debug` when it is installed, else by reducing what the two fixes share to one claim and testing it with the failing test. The check is advisory, and a skip names both claims.
- `fix-until-green` returns `stalledRootCauses` on a `no-progress` stop: the root causes the fixers acted on in the two stalled rounds. The diagnose skill reports the claim they share as the premise the run did not test.
