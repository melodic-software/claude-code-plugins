---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: the changed-line ranges no longer read an added line starting `++ b/` as a file header, so findings in the hunks after it stay with their real file.
