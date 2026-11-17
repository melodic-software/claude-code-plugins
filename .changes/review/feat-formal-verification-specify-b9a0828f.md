---
bump: patch
---

### Changed

- The shared config cascade copy now exports its `fileState` and `escapes` path guards, so a script that reads other repository files can refuse a symlink or a path outside the checkout the same way. Nothing that already used the cascade changes.
