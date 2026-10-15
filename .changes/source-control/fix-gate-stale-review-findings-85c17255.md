---
bump: patch
---

### Fixed

- The unattended merge gate no longer counts an AI review finding from an earlier round as open
  once its thread is resolved and the lane has reviewed a later head: a resolved thread opened
  before the latest review on the pinned head is closed whoever resolved it, while a thread from
  that latest review still needs a human to resolve it.
