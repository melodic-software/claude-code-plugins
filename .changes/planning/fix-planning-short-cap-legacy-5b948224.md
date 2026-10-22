---
bump: patch
---

### Fixed

- The 1:1 interview page no longer refuses every write to a session holding a `short` over 80 characters: a stored `short` up to 500, the earlier cap, still loads, and answers and edits to other fields save. Only a write that sets a new or changed `short` is held to the 80-character cap.
