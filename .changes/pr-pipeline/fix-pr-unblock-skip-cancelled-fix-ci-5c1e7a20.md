---
bump: patch
---

### Fixed

- The fix-ci dispatcher no longer dispatches a head whose tested run ended `cancelled` when no check on the head failed, timed out or failed to start. fix-ci-context fixes only those, so each such run posted `Skipped: not-applicable` and spent the head's per-head cap on nothing (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
