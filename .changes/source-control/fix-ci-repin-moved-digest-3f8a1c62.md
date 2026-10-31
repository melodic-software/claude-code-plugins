---
bump: patch
---

### Fixed

- `ci --ci` re-pins a digest pin the pull request's own change moved, with the re-pin script the test file names, after confirming the guarded defense still holds, and reports the check fixed. It escalated every such pin as `weaken-required`, so the fix-ci lane stopped each pull request that edited guarded text. It still escalates `weaken-required` when its own fix would change guarded text, when the same test fails on something other than a digest, or when the test file names no re-pin script.
