---
bump: patch
---

### Fixed

- The unattended merge gate no longer counts an AI review finding from an earlier round as open
  once its thread is resolved, its lines have changed, and the lane has reviewed a later head: such
  a thread is closed whoever resolved it. A thread from any review of the latest reviewed head, or
  one whose lines never changed, still needs a human to resolve it.
