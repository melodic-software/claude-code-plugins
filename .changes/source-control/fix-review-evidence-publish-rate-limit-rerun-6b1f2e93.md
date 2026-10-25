---
bump: patch
---

### Fixed

- `/source-control:babysit-prs` binds a review lane's second attempt when the first failed because posting the review hit GitHub's API rate limit: a `failure-class=publish-failed` line whose detail opens with `API rate limit exceeded` or `You have exceeded a secondary rate limit`. Such a re-run was refused as `rerun-not-allowed`, which left later incremental reviews unbound (`incremental-gap`). Any other publish failure still refuses the re-run.
