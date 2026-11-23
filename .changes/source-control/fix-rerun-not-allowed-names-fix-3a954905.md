---
bump: patch
---

### Changed

- The merge gate's `evidence-unbound:<lane>` hold with the reason `rerun-not-allowed` now names
  the fix: the merge gate's whole-review request clears it with a new run at the same head, and
  when that request skips (for example on `running-jobs`), `gh pr update-branch <n>` gives the pull
  request a fresh head; never hand-rerun the lane run. The GitHub provider's babysit-prs safety
  reference states when a review lane's re-run attempt binds and what clears a refused one.
