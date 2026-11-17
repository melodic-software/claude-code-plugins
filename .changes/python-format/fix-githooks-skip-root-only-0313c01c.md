---
bump: patch
---

### Fixed

- The format and lint entries skip only the root `.githooks/` directory, where the installer puts its copies, again; a Python file under a nested `.githooks/` directory is formatted and linted.
