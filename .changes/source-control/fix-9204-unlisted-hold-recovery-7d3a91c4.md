---
bump: patch
---

### Fixed

- The post-merge check no longer holds the pr-merge lane forever when a github-actions[bot] dispatch run's `pr-merge-dispatched-<id>` record listing reads empty twice past the dispatch deadline. The unreadable verdict now sets `needsDispatch`, so pr-merge starts and records a fresh full run, unless a recorded lane run created after the deadline is still running. That later run clears the hold only when its record is listed, github-actions[bot] dispatched it on the branch, its head contains the merge commit, and it passes; any other later run leaves the verdict unreadable.
