---
bump: patch
---

### Fixed

- ci-status and the auto-merge arming step no longer read a member writing "the `do-not-merge` label" as a veto. Any other `do-not-merge`, a comma list included, and a sentence that says not to merge still hold the merge.
