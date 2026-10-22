---
bump: patch
---

### Fixed

- The post-merge check no longer demotes unattended merging when the artifact listing for a github-actions[bot] dispatch run's `pr-merge-dispatched-<id>` record answers empty. It reads the listing once more, and when the second read is also empty and the run was created by the dispatch deadline, the verdict past the deadline is unreadable instead of a dispatch failure. A listing that names a sender other than the lane's pr-merge.yml still reads as not the lane's run.
