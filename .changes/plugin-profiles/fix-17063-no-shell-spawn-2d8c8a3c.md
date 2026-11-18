---
bump: patch
---

### Fixed

- On Windows, `start` and the commands that list plugins or sessions no longer print Node's DEP0190 warning: they run the `claude.exe` on PATH without a shell.
