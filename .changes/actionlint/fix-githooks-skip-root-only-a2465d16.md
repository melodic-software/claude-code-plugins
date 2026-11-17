---
bump: patch
---

### Fixed

- The lint entry skips only the root `.githooks/` directory, where the installer puts its copies, again; a workflow under a nested `.githooks/` directory is linted.
