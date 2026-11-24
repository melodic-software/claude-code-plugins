---
bump: minor
---

### Added

- pr-verify's verdict records `trusted_actors_blob`, the git blob id of the standards trusted-actor list the run judged with, which the merge gate compares with the live list. The resolver (`specChanged`) and the lost-run reconciler (`prefilterSpec`) count a pass that started before the committer time of the newest standards commit touching that list, at the run's standards SHA, as `spec-changed`, so the head is judged again; a change to any other standards file is not one. That time is one commits API read a run.
