---
bump: patch
---

### Fixed

- `/app-control:map refresh` switches back to the branch it started on after every pass, not only between control skills in a multi-skill pass. A one-feature refresh called from `/testing:run-e2e` or `/verification:confirm` on a ticket branch no longer leaves the caller on `control-skill-upkeep/*`.
