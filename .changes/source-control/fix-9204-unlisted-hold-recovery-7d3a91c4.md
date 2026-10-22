---
bump: patch
---

### Fixed

- The post-merge check no longer holds the pr-merge lane forever when a github-actions[bot] dispatch run's `pr-merge-dispatched-<id>` record listing reads empty twice past the dispatch deadline. The unreadable verdict now sets `needsDispatch` once per merge, so pr-merge starts and records one fresh full run; any github-actions[bot] dispatch after the deadline, recorded or not, uses up that one run. A completed later run judges the merge only when its record is listed, github-actions[bot] dispatched it on the branch, and its head contains the merge commit: one that passes clears the hold, a red one with checks newly failing is a dispatch failure, and a red attempt 1 waits for the lane's re-run. Any other later run leaves the verdict unreadable. The report's new `hold` field names the case, and `recovery-unrecorded`, the recovery run's record missing too, makes pr-merge emit an error.
