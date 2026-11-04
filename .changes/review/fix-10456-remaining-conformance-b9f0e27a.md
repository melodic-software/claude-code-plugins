---
bump: patch
---

### Fixed

- `/review:fanout` run-everything mode no longer says a leaf with no `effort:` key ran at the
  session's level: that holds only on the main conversation's model. The `@session` label is
  unchanged.
