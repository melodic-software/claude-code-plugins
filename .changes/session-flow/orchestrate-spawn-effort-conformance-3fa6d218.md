---
bump: patch
---

### Fixed

- `/session-flow:orchestrate`: the session's effort reaches an unpinned spawn that passes no `effort`
  only on the main conversation's model, and the addendum now says so. Two `worker_continuation`
  pointers move to the section that holds their text.
