---
bump: patch
---

### Fixed

- `pull-request comments --ci` treats the `line` of every thread with a direction as possibly
  stale, not only a fix request's, since a trusted reply after an escalation can now also start
  work on a thread from a review of an earlier head.
