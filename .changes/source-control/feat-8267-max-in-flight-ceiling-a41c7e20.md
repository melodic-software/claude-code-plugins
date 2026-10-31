---
bump: minor
---

### Changed

- The unattended merge gate reads a `merge.max-in-flight` above 24 as unset instead of taking it,
  and the pipeline schema states the same maximum.
