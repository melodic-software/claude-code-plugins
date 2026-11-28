---
bump: minor
---

### Added

- `work-item-tracker` and `/work-items:morning-brief` add phase-2 dual-write and dual-read support for native GitHub Issue Statuses (`set-native-status` verb, best-effort `create-item`, `claim`, and `done` transitions, `native_status` on `get-item` and `list-items`, and REST `Native statuses (open)` counts in `morning-brief`), degrading cleanly when un-enrolled or `null` while keeping `Work status` and trusted-actor verification untouched.
