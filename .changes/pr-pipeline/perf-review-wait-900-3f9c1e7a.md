---
bump: patch
---

### Changed

- `ci-status`'s review-lanes step waits up to 15 minutes for an unfinished review lane instead of 8, and stops 4 minutes before the job's 30-minute timeout rather than 2 minutes before `gh_read`'s deadline, so a lane whose last job waits 9 to 13 minutes for a runner is judged in the same run instead of failing and waiting about 30 minutes for `rerun-ci-status`.
