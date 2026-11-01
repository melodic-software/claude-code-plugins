---
bump: patch
---

### Fixed

- `ci --ci` re-pins a digest pin the pull request's own change moved, after confirming the guarded defense still holds, and reports the check fixed. It is told to run the re-pin script only through the wrapper the runner names over the base's copy, never a copy in the checkout, which the pull request can edit; the lane does not enforce that route, so review of the patch is the control. It escalated every such pin as `weaken-required`, so the fix-ci lane stopped each pull request that edited guarded text. It still escalates `weaken-required` when its own fix would change guarded text, when the same test fails on something other than a digest, or when the runner names no wrapper for the test's re-pin script.
