---
bump: patch
---

### Fixed

- babysit-prs: the merge gate no longer refuses a pull request with `no-lane-job` when an earlier head's review attempt failed because its kill-switch job failed before the lane job ran. Such an attempt reviewed nothing; the pinned head still needs its own successful review.
