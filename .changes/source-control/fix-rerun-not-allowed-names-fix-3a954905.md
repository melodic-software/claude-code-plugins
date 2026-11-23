---
bump: patch
---

### Changed

- The merge gate's `evidence-unbound:<lane>` hold with the reason `rerun-not-allowed` now names
  the fix: the merge gate's whole-review request clears it with a new run at the same head, retried
  on a later sweep when a limit skips it; at the per-PR cap of two requests, or once that head's
  request has run, a new head clears it
  (`gh pr update-branch <n>` when the branch is behind its base, else a new commit); never
  hand-rerun the lane run. The GitHub provider's babysit-prs safety
  reference states when a review lane's re-run attempt binds and what clears a refused one.
