---
bump: patch
---

### Changed

- A removed `agent-ready` no longer keeps an issue out of the issue lane for good. Intake admission and work-unblock leave it out only until the lanes App or a listed human adds `status: ready` after the newest removal; then admission runs its rules as usual. A `status: ready` added by anyone else, or before the removal, does not lift it, and a lane restart still does not count as a removal.
