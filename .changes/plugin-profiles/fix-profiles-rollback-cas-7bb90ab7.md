---
bump: patch
---

### Fixed

- An apply whose settings write fails now undoes its record only while the record file still holds the one it wrote, so a second apply that saved its record in between keeps it, and `clear` and `reset` can still undo that apply.
