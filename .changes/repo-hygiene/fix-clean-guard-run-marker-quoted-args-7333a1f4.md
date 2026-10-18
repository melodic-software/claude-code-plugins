---
bump: patch
---

### Fixed

- The clean skill's destructive guard now gates only while a mutating clean run is open, tracked by a per-session run marker that `scan` and `scan-batch` never write, so it no longer blocks unrelated commands for the rest of the session.
- On the Bash tool the guard matches each command's parsed words instead of the raw text, so destructive text inside a quoted argument (an issue comment body, a commit message) no longer blocks the command.
