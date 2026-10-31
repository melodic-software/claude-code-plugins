---
bump: minor
---

### Changed

- The read-only `audit` action of `/harness-ops:plugins` is now its own skill,
  `/harness-ops:plugins-audit`, which the model may start. `/harness-ops:plugins` keeps `sync` and
  `converge` and stays user-only, because `sync` can update committed plugin pins in every
  repository on disk. `/harness-ops:plugins audit` now points to the new skill instead of running
  the dry run.
