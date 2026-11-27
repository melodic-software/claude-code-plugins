---
bump: patch
---

### Fixed

- `/performance:go-faster` no longer skips its sweeper when the prompt names the speedup it wants in adopt-now; a named speedup is adopted only when the sweeper's report lists it. A requested speedup or change to how the session works that the report does not list is declined, while ordinary task work is not: lower effort, a smaller model or shallower verification as `flag-only`, skipping or removing a check by routing it to `/overengineering:audit`, and any other speedup as not in this report, for the next run to measure.
