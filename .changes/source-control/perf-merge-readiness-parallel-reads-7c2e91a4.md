---
bump: patch
---

### Changed

- The pull-request skill's merge readiness check reads the reviews, check runs, commit statuses, review threads and pr-verify settings in parallel once the pull request itself is read, about 2 s faster on a ready PR. What it checks is unchanged.
