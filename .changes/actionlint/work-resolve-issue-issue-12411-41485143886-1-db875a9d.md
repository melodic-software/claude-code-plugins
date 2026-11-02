---
bump: patch
---

### Fixed

- On a merge commit, the pre-commit check now reports findings only on the lines that the merge's
  conflict resolution adds. A finding on a line the merged branch already holds no longer blocks the
  merge. Outside a merge, the check still reports findings on every line the commit adds.
