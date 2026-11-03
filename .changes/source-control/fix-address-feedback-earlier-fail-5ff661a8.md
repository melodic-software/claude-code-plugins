---
bump: patch
---

### Fixed

- The `comments --ci` review-thread tool (`feedback-thread.sh`) takes the notes of an earlier pr-verify FAIL as work items: `notes` lists them, and `record` takes `VALID` or `already-addressed` (with evidence) for a `VNOTE_` id, with each note's path in the fix's scope. The pr-unblock lane uses this when the merge gate refuses a head `verify:earlier-fail` and the FAIL's threads are already resolved.
