---
bump: patch
---

### Fixed

- The dispatchers' FAIL-cap read waits and reads a carried artifact listing again when it misses
  GitHub's live count, instead of going straight to a whole listing that no longer fits in
  `verify-cap.mjs`'s 120 s limit. A miss of 2 on #11354 otherwise ended a round in
  `verify:unreadable`. The reader's waits stop at the caller's limit, and a miss that outlasts
  them still refuses.
