---
bump: patch
---

### Fixed

- A profile started or launched from the home folder now switches plugins: the home folder's `.claude/settings.json` is the user settings file, which was read a second time as the project level, so every plugin that file set was left alone.
