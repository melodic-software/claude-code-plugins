---
bump: patch
---

### Fixed

- The merge gate no longer dequeues a queued lanes App pull request that changes only
  `merge.baseline-file` for having no pr-verify verdict (`verify:missing`). The queue re-check now
  applies the same native-baseline exemption the arming step already applies, so such a pull
  request stays in the merge queue with no linked issue and no verdict.
