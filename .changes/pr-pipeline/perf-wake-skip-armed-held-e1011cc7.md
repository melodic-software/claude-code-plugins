---
bump: none
---

No release: pr-verify's `wake-pr-merge` job no longer dispatches pr-merge for a lanes App pull request that is already armed or carries `do-not-merge`; the scheduled sweep makes the same decision for those, so only the wake's run count changes.
