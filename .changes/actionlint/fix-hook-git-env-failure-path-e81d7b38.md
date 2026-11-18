---
bump: patch
---

### Fixed

- When the inherited `GIT_CONFIG_COUNT` is not a number, the end-of-turn check still blocks the turn end, and now prints one stderr line saying why instead of an empty message.
