---
bump: patch
---

### Fixed

- The post-merge check treats a red attempt 1 of a full run as settled, not awaiting a re-run, once a
  newer full run it already listed passed on a descendant commit on the branch, so such a run holds
  no merge pending and is never named for the lane re-run.
