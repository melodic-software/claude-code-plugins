---
bump: minor
---

### Added

- `/app-control:drive ready` reports whether the session can extract a screen recording's frames and read them as images, from an optional `frames` row in the hub's `## Capture`; a missing extractor or image reading is a capability gap naming the narrowest tool or grant. `report.json` records it as `ready.frames`.
- Feature files may end `## Drive` with performance budget lines, `Budget: <measure> | <source>`. The threshold comes from the new config field `budgets.<feature id>.<measure>`, never from the feature file or a default. Drive records each measured value beside its threshold and layer (or `unset`) in the new `report.json` `budgets` field and never compares them.
