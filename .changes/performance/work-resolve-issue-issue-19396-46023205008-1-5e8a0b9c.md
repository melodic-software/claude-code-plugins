---
bump: patch
---

### Fixed

- `/performance:go-faster` no longer skips its sweeper when the prompt names the speedup it wants in adopt-now; a named speedup is adopted only when the sweeper's report lists it. A requested change outside the report is declined: lower effort, a smaller model or shallower verification as `flag-only`, and skipping or removing a check by routing it to `/overengineering:audit`.
