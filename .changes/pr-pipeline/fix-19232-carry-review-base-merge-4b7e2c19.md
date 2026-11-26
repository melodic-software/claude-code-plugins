---
bump: patch
---

### Fixed

- The hosted review lanes run no model on a head that only merges the base branch into the reviewed head: ci-workflows `resolve-review-scope` records `skip=no-change` through the last review when every commit since it (up to 5) is a merge of a commit the base branch holds whose tree is the conflict-free automatic merge of its parents (an empty `git show --remerge-diff`), before the 300-file and base-overlap limits that sent such a head to a whole review. A conflict resolution, an extra change in the merge, a merge of a branch the base does not hold, or any failure to check is reviewed as before.
