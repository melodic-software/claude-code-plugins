---
bump: patch
---

### Fixed

- `ci-status` no longer tries to turn off an armed pull request's auto-merge on a push: turning
  it off needs `contents: write`, which the lanes App's arming token holds and `ci-status`'s
  `GITHUB_TOKEN` deliberately lacks, so the mutation could not succeed. The merge queue's check for
  a pr-verify pass at the exact head it merges is what holds a new head.
