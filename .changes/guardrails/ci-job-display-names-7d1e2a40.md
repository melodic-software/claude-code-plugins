---
bump: patch
---

### Changed

- The `merge_guard_ignored_checks` default is `github-actions:Merge,github-actions:merge`: the
  pr-merge job's check is now `Merge`, and `merge` on a head tested before the rename.
