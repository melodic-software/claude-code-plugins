---
bump: patch
---

### Fixed

- The merge gate's security count reads each earlier review's `critical-findings:` line from the reviewed-head marker's edit history, so an IMPORTANT summary finding an earlier review reported no longer holds the pull request once a clean incremental review covers the head; a history that is missing, truncated, deleted, edited by anyone but the lane, or carries no single line still counts every finding.
