---
bump: minor
---

### Changed

- `/session-flow:workflow`'s explore stage no longer asks before investigating a file that is
  missing from disk. It first runs `git status` and `git log` on that path, both read-only.
  A staged or committed delete counts as intentional: the stage skips it and says so. A file
  deleted only in the working tree is investigated. The stage asks only when neither command names
  the path or a command fails.
