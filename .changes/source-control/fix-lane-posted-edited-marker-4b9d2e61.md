---
bump: patch
---

### Fixed

- `/source-control:babysit-prs` counts a review lane's reviewed-head marker as posted when the lane rewrote it in the window, not only when it created it then. The lane edits one marker in place, so a marker an earlier run created kept its old creation time, and a lost or no-outcome first attempt that had already rewritten it could still bind the second attempt or trigger the gate's re-run. Each revision in the marker's edit history now counts, and a missing or unreadable edit time or history counts as posted.
