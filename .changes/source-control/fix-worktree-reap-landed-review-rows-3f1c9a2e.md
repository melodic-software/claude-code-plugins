---
bump: patch
---

### Fixed

- `landed-work.sh --merged-pr-proof` looks up a branch's merged pull requests by name when the newest-1000 listing is full and the branch is not in it, so in a busy repository a worktree whose PR merged at its head before that window is proven landed instead of sent to `worktree-reap` review.
