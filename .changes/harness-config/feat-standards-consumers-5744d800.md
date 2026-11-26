---
bump: minor
---

### Added

- `/harness-config:audit-automation-gaps`'s rule inventory counts each statement of the files the org layer's printed index lists (`scripts/org-standards.sh index`) as an automated-review row, labeled by the file's path in the org checkout, and names any listed file it could not read. Personal subscriptions stay named as present, not counted.
