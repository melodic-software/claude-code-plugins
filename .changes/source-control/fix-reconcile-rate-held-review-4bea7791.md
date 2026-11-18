---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: the merge gate binds a review lane's attempt 2 when a leg of attempt 1 held on a GitHub API rate limit: the lane job left its `held:` notice for the head and no completion record, and the leg's annotations show the hold beside a 403 or 429 at remaining 0. The lane-run read now fetches the annotations of a green leg whose `Claude review` step skipped, and the saved lane-run format moves to `v2` so no record saved without them is used.
