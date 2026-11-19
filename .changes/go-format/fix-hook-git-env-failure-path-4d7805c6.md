---
bump: patch
---

### Changed

- When the inherited `GIT_CONFIG_COUNT` is not a number, the end-of-turn check still runs no git and passes, and now prints one stderr line saying why.
