---
bump: patch
---

### Changed

- `babysit-prs`: the merge lane no longer treats `human-merge-hold` as a hold label; the lanes App
  now marks a pull request a person merges with `do-not-merge`, which the lane already holds.
