---
bump: patch
---

### Changed

- Each Refine fix-docs call (the first, the subscription and the fallback leg) runs its model leg
  for at most 15 minutes, down from 45: its run job's timeout is 30 minutes, down from 60. A hosted
  review's `wait-refine` job now waits up to 30 minutes for Refine, down from 40.
