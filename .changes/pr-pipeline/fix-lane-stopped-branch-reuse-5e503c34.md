---
bump: patch
---

### Fixed

- A work-resolve-issue run now deletes the issue's leftover lane branches from earlier stopped runs: a branch whose run posted an outcome marker, whose commits are all the lanes App's, and that has no pull request in any state. `issue-prior` names them from the reads it already makes, sparing the branch the run reuses, resumes or starts fresh past and every branch of the run itself, and a new `prune-lane-branches` job, the lane's only `contents: write`, re-checks every named branch in one GraphQL read and deletes each with one `updateRefs` at the tip it read. The stale-branch comment now says the next run deletes the branch instead of promising no lane does.
