---
bump: patch
---

### Changed

- `/harness-ops:plugins` cache-content check reads its `git ls-tree`, `find` and `git check-ignore` output from a temporary file instead of a pipe, so bash reads it in blocks rather than one byte per read call, and finds each path's owning source and install root once per directory rather than once per file. The report is unchanged.
