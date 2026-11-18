---
bump: patch
---

### Fixed

- When the inherited `GIT_CONFIG_COUNT` is not a number, the end-of-turn check is skipped: the hook prints one stderr line saying so and exits 0, where it used to block the turn end with an empty message.
