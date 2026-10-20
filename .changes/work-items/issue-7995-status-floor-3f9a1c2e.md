---
bump: minor
---

### Changed

- `list-frontier --autonomous` now excludes items labeled `status: needs-decision` or `status: needs-info`, even when they also carry the autonomous-eligible label. The default (attended) frontier still lists them.
