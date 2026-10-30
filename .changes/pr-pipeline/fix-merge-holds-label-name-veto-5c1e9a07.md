---
bump: patch
---

### Fixed

- ci-status and the auto-merge arming step no longer read a member naming the `do-not-merge` label (in backticks, before "label", or as a list item after a comma) as a veto. A sentence that says not to merge, or a bare `do-not-merge`, still holds the merge.
