---
bump: patch
---

### Fixed

- The once-a-day CLI version check no longer deletes a lock another session has just created: when the lock it found disappears before its age is read, the shared `cli-version-check.mjs` retries instead of treating it as stale.
