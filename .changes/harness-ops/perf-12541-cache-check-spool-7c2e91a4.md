---
bump: patch
---

### Changed

- `/harness-ops:plugins` cache-content check reads its `git ls-tree`, `find` and `git check-ignore` output from a temporary file instead of a pipe. On Linux and macOS, bash then reads that output in blocks instead of one byte per read call; Cygwin and MSYS2 builds of bash read one byte at a time either way. The check also finds each path's owning source and install root once per directory instead of once per file. The report is unchanged.
