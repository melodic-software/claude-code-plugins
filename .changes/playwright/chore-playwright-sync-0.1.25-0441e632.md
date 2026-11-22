---
bump: patch
---

### Changed

- `/playwright:playwright` is synced to `@playwright/cli` 0.1.25. The sessions reference now attaches to the user's own browser through the extension with a named session, keeps the user's tabs on detach, and points at upstream's extension section before any tab cleanup.
