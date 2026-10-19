---
bump: patch
---

### Fixed

- `pull-request comments --ci` now records `UNCERTAIN` with evidence, and edits nothing, when a
  directed finding no longer shows in the current code, and treats a requested thread's `line` as
  possibly stale, since a fix request can start a thread from a review of an earlier head.
