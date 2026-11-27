---
bump: patch
---

### Changed

- The merge guard reads the reviews, check runs, commit statuses, review threads and pr-verify settings in parallel once the pull request itself is read, so a merge on a ready PR waits about 4.5 s instead of 6.5 s. What it checks and how it reports a failed read are unchanged.
