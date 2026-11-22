---
bump: patch
---

### Changed

- The unattended-merge paragraph states that a CRITICAL an earlier head's
  main-run security review recorded stops holding once the pinned head's own
  main-run security review binds with no CRITICAL finding; until then it holds,
  so a push no review has covered cannot clear it.
