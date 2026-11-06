---
bump: patch
---

### Fixed

- The landed-work engine behind `/source-control:worktree cleanup` and the daily worktree reap no longer discards its base patch-id set when the base holds an empty commit, such as an empty squash merge. Such a commit has no patch to hash; it is now excused once `git diff-tree` shows its diff is empty, so every worktree stops rebuilding the base set and falling through to the merged-PR read. A failed merged-PR read now names gh's own error in its reason.
