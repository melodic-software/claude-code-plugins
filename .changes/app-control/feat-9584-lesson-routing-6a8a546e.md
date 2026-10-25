---
bump: minor
---

### Added

- `/app-control:map` create and refresh place a lesson learned while driving by its scope: a lesson about one feature goes in that feature's `## Gotchas`, one that holds for every feature goes in a new optional `## Gotchas` section of the control skill's hub, and any other lesson is written nowhere in the control skill and reported for `/corrections:codify`. In refresh a placed lesson is doc drift and ships in the upkeep pull request.
- `/app-control:map refresh <feature>` narrows the source wave and live pass to one feature of the control skill that holds it; a clean narrowed pass records no state.
