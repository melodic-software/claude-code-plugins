---
bump: patch
---

### Fixed

- babysit-prs: the merge gate no longer refuses a pull request with `no-lane-job` when an earlier head's review attempt failed before its lane job ran, for example a kill-switch job that crashed. Such an attempt reviewed nothing; the pinned head still needs its own successful review.
