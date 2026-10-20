---
bump: patch
---

### Fixed

- The review-threads round records the SHA-256 of the thread file before the model runs, and the branch move and the reply collection read the file only when it still matches; otherwise the PR branch is not moved and no replies are collected ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).
