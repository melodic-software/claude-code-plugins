---
bump: patch
---

### Fixed

- `pull-request ready`: after the flip, the runs created for the head are checked for a `skipped` conclusion for up to 180 seconds, so a late draft-payload run whose lanes skipped is no longer taken for a ready run. A skip re-fires the ready event once (undo, then ready), sharing that one re-fire with the missing-run toggle, and a second skip is reported rather than re-fired.
