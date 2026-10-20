---
bump: patch
---

### Fixed

- `/harness-ops:audit-performance` no longer counts `Edit(**/<dir>/*.<ext>)` and `Write(*.<ext>)` hook gates as firing on a file of another extension, and each `fan_out.hooks.projection` row now reports a `floor` and a `ceiling` beside its existing fields, with each extra copy of a settings-file handler and each upper-case extension gate counted toward the ceiling only (#6786).
