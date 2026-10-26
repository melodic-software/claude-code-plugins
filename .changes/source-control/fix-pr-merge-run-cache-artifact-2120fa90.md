---
bump: patch
---

### Fixed

- The babysit-prs merge-skip and verdict-evidence scripts now say where pr-merge's carried store comes from: the `pr-merge-run-cache` artifact of a trusted run on main, no longer an Actions cache entry (#9455). Behavior is unchanged. A carried read still counts only toward a FAIL, and a carried refusal can only repeat a refusal.
