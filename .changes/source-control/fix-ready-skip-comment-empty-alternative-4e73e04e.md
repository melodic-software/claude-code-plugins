---
bump: patch
---

### Fixed

- `ready --skip` breaks a closing keyword in the recorded reason on every bash: the guard's regex had an empty alternative that some bash builds reject, so the keyword reached the comment intact.
