---
bump: patch
---

### Fixed

- The PR monitor's poll keeps its check baseline when a check read fails, so a failed first read no longer makes the next poll emit every check that had already finished.
