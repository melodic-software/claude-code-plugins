---
bump: patch
---

### Fixed

- The hosted review lanes run no model on a head that only merges the base branch into the reviewed head when the merged-in base changes touch no file of the pull request, even when the base moved 300 or more files: ci-workflows `resolve-review-scope` records `skip=no-change` through the last review when every commit since it (up to 5) is a merge of a commit the base branch holds whose tree is the conflict-free automatic merge of its parents (an empty `git show --remerge-diff`). A merge whose base side changes a file of the pull request, a conflict resolution, an extra change in the merge, a merge of a branch the base does not hold, or any failure to check is reviewed as before.
