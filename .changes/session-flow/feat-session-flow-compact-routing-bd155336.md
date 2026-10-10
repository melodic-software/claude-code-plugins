---
bump: minor
---

### Changed

- `/session-flow:workflow`'s continuation router makes `/compact` the default within a phase or activity and lets it repeat; an already-compacted session no longer routes to a handoff for that reason.
- Switching to unrelated work hands off when anything carries over and plain `/clear`s when nothing does.
