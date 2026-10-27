---
bump: patch
---

### Fixed

- `/source-control:pull-request list` returns `isCrossRepository` and `headRepositoryOwner` for each pull request, so a caller can tell a fork's pull request from the repository's own when both share a head branch name.
