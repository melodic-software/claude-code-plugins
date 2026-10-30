---
bump: patch
---

### Fixed

- The babysit merge gate follows a no-change skip through clean base merges, up to 10 earlier heads (the cap ci-status shares), back to the newest reviewed head, instead of stopping after one hop and scoring a reviewed pull request as unreviewed. A merge that changed content still needs its own review.
- The pull-request skill evals cover the remerge-diff rule: a base merge with an empty remerge-diff carries the earlier review forward, and a non-empty one needs a substitute review.
- Readiness Gate 5 no longer marks a review lane absent on a base merge whose `git show --remerge-diff` is fully empty: it applies B2's test, and the review on the pre-merge head counts.
