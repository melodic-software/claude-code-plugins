---
bump: patch
---

### Fixed

- pr-review-main skips a lane-source pull request's review as already done only on verdicts from runs created after the pull request's newest base change, the cutoff the merge gate applies. A pull request retargeted without a push is reviewed again instead of staying held as `lane-source-changed`.
