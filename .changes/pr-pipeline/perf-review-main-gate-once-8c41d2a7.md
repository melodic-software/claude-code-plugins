---
bump: patch
---

### Changed

- pr-review-main runs the trigger gate and reads the pull request's file list once per run, in a
  new `trigger` job, instead of once per review lane. The key leg takes that job's result (the
  gate's verdict, the PR number, the head and base SHAs and the lane-source flag, each checked
  against a fixed shape) only when it comes from the same run attempt, and gates itself otherwise,
  so a lane re-run alone still checks its own re-runner and the reconciler's record. The later legs
  still gate themselves. The file list read now goes through the api-budget gh wrapper, so its
  requests are counted.
