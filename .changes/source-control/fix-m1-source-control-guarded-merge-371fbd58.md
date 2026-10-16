---
bump: patch
---

### Fixed

- `pull-request` merge after AI review: the checks script now prints the verified head instead of merging, and the merge runs as one command with its guard (head, author, fork, draft, changed files, review checks) and literal PR number, `-R` and sha, so an auto-mode allow entry that requires that guard can match it. A guarded `--admin` form is given for repositories where the user's own instructions authorize admin merges.
