---
bump: patch
---

### Fixed

- `/work-items:work` and `/work-items:ship run` carry a human-merge hold into the PR body before the ready flip: when a commenter with write access on the item asked for `Hold: a human merges this`, the new `scripts/merge-hold.sh` prints that line and the orchestrator adds it to the body, so the babysit merge gate holds the merge. A failed read leaves the PR a draft.
