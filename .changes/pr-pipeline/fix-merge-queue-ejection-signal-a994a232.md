---
bump: patch
---

### Fixed

- The monitoring lane's signal 4 (`merge-queue-ejections`) counts the merge queue's removals of pull requests for failed checks, read from the timelines of the pull requests whose merge groups failed, not failed merge-group runs: a group the queue rebuilt behind an entry that left removed nothing. A removal a hold caused after the enqueue is not counted: a `do-not-merge`, human-gated, `pr-verify-failed` or `security: outside-actor` label added while queued, or a failed group whose queue-hold step names the lanes kill switch. The title and summary carry the removal count, and a listing past 100 failed runs or 50 pull requests, or a pull request timeline past 100 items, leaves the signal unread.
