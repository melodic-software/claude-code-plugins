---
bump: patch
---

### Fixed

- The fix-ci dispatcher now retries a head whose fix-ci run its push job stopped, as designed. Its
  first pass read only the check rollup, where a stopped run's `Passed: no changes` fix-ci check
  looks final, and dropped the head before the REST read that counts the stop. A head whose rollup
  holds a lane-stopped or kill-switch `pr-unblock / apply-patch` check now goes on to that read and
  gets its `fix-ci-restarts` retry under the per-head cap.
