---
bump: patch
---

### Fixed

- The GitHub adapter's "Close item" posts the closing note as its own comment and then closes, instead of passing it to `gh issue close --comment`. On an issue that was already closed, `gh` skipped the comment and exited 0, so a `/work-items:track done --summary` note (and a triage, recheck or stale close note) was lost while the run reported the item closed. The duplicate-close forms also post their note as a separate comment. `done` now reports an already-closed item as already closed, with the summary added.
