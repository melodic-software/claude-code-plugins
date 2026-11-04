---
bump: patch
---

### Fixed

- `/bugs:scan`: a stage that passes no `effort` runs at the session level only on the main
  conversation's model. The run metadata labels a stage on another model `unset` rather than
  `session`, and a gate on another model passes the session's level to stay at or above it.
