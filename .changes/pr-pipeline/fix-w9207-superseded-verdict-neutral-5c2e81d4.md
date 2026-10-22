---
bump: patch
---

### Fixed

- pr-unblock's `fix-docs` reports its check on the head it ran on when the PR head moves while it
  runs, instead of posting failure on the new head and blocking the merge. A new `fix-docs-head`
  job, which runs no head code, reads the head both `fix-docs` calls pass as `head-sha`; a run head
  that matches no gated head still posts failure. The read runner's new `post-decline` input
  (default `true`) is `false` for fix-docs, so a run that stops before its trigger gate posts
  nothing and the once-per-PR dispatcher tries the PR again.
