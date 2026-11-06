---
bump: patch
---

### Changed

- The read-safety measurement's closing line is now a topology check that states what it proves: every call returned within the lock and request timeouts, and no transaction was left open. Its two timeout clauses could not fail, since a call that hits either timeout ends the run before results are written. The doc points at the waiting-tasks table and the worst-case line for how long anyone waited, and says no writer-wait limit is set (#5940).
