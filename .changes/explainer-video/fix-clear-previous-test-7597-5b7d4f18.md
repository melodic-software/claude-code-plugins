---
bump: patch
---

### Fixed

- The empty-output-folder render test now asserts the folder is still empty after `clear_previous`, so it fails if the cleanup creates files.
