---
bump: patch
---

### Changed

- pr-merge's `enable-auto-merge` job skips its work, green with a notice, when another run's `enable-auto-merge` job still waits and does the same work, so a backlog of events costs one pass instead of one serial pass each. On a pull request event it runs only for a lanes App pull request (`AUTOMATION_LANES_APP_SENDER_ID`), so any other pull request's check reads skipped instead of pending behind the queue.
- pr-merge's merge job reuses its run's `post-merge-dispatch` check when that check judged main at the merge job's commit under ten minutes ago, instead of running the same check again.
- The merge and `enable-auto-merge` jobs read main's pr-merge run listing, each run's artifact list and each compare once between their kept-file readers (the gate cursor, the head-ref map and the lane records).

### Fixed

- A merge job no longer skips its gate citing a pending run whose merge job already ran: a run reads pending while any one of its jobs waits, so the skip now reads the pending run's jobs and counts it only while its merge job still waits.
