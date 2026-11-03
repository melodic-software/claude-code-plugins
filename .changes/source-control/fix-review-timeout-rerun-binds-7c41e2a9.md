---
bump: patch
---

### Fixed

- The merge gate's review evidence binds an AI review run's second attempt when the first failed with `failure-class=timeout` and the lane posted nothing on the head, the same unposted proof `no-outcome` uses. The gate still never starts that re-run itself.
