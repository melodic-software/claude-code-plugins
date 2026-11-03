---
bump: minor
---

### Added

- `/work-items:work` in the issue lane has a verify-and-close mode for a parent whose sub-issues are all closed as completed. When `issue.json` carries `verify_close`, the run builds nothing and checks each of the parent's own done-when items, citing the evidence for each. It then stops `verified-done`, which closes the parent, or `verify-unmet`, which names the unmet items and parks the parent.
