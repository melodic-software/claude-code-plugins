---
bump: patch
---

### Fixed

- Check review upstream runs against the broker actor and attempt rule in `feedback-dispatch.mjs` (`trustedReviewRun` and `reviewRunAt`): when a review run was re-run by `github-actions[bot]`, fall back to a broker-accepted sibling review run on the same head, or skip with a logged reason naming the attempt and triggering actor when none exists.
