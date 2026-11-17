---
bump: minor
---

### Added

- `/testing:write` keeps every test's writes, and the code under test's, in a temporary directory
  removed on every exit path, and runs a test of a destructive command only in a throwaway sandbox.
