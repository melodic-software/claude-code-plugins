---
bump: patch
---

### Fixed

- work-unblock closes a split parent as completed only when every sub-issue closed as completed
  and the parent's done-when is covered. A sub-issue closed as not planned, as a duplicate or with
  no reason leaves the parent open, and so does a split record that leaves an item out, a split by
  hand with no task list, or an open task item in a listed human's comment on the parent.
- The lanes App's close of a split parent counts as done for what it blocks only under that same
  rule (`admit.mjs` `splitLeftOpen`).
- work-unblock's sweep sends a parent with no open sub-issue through admission even when GitHub's
  sub-issue summary still shows a wait, so a parent with a duplicate sub-issue gets its one
  admission note instead of a stale wait.
