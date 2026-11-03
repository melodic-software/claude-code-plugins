---
bump: minor
---

### Added

- `/corrections:codify note --applied` records a change already made: the row carries `"kind": "applied"`, its `signal` names the situation the change targets and the action it should prevent, and `source_id` is the change's `#PR` or commit when given (#12884).

### Changed

- `/corrections:codify group` leaves applied rows out of its by-mistake groups and counts and lists them apart (#12884).
