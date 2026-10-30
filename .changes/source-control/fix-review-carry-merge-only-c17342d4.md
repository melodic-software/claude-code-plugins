---
bump: patch
---

### Fixed

- The babysit merge gate follows a no-change skip through any number of clean base merges back to the newest reviewed head, instead of stopping after one hop and scoring a reviewed pull request as unreviewed. A merge that changed content still needs its own review.
- The pull-request skill evals cover the remerge-diff rule: a base merge with an empty remerge-diff carries the earlier review forward, and a non-empty one needs a substitute review.
