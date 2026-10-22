---
bump: patch
---

### Fixed

- The post-merge check no longer demotes unattended merging when a run listing answers without the dispatch runs it holds. Before a missing dispatch run becomes a failure, it reads the dispatch runs at the merge commit and at each later commit on the branch made by the deadline. A run there that the listing lacked, and that could have counted in time, makes the verdict unreadable. So does a listing whose `total_count` exceeds what it returned, unless it is past GitHub's 1,000-result search cap: that listing reads, with a `listing-capped` warning in the verdict.
