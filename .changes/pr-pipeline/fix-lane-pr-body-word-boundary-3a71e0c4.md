---
bump: patch
---

### Fixed

- The hill-climb lane's draft pull request body no longer cuts a pass summary in half. A summary longer than 24000 characters is now cut at its last whitespace inside the cap, before the existing `(cut at 24000 characters; ...)` line; one token longer than the cap is still cut at the cap, never inside a surrogate pair.
