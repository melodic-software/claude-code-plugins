---
bump: patch
---

### Changed

- The issue lane runs up to 6 resolve-issue runs at once instead of 3 (`SLOTS` in `work-resolve-issue.yml`), so agent-ready issues no longer wait three at a time.
