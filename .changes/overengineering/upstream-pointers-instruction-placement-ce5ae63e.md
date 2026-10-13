---
bump: patch
---

### Changed

- `/overengineering:audit` and `/overengineering:delta` share one record of why their `context/` files write `<plugin-root>`, in the new `reference/spoke-paths.md`, with an anchored pointer to the plugins reference, in place of two restated copies of the variable-resolution behavior.
- The delta lane's recurring-wiring guide keeps its fixed-interval advice but no longer restates the scheduler's interval, jitter, expiry or provider behavior. It points at the live scheduled-tasks sections instead, dropping a restated provider and version list the page no longer supports as written.
