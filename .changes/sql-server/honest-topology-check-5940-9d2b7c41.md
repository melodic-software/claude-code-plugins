---
bump: patch
---

### Changed

- The read-safety measurement's closing line is now a topology check that states what it proves: no agent lock wait reached the lock timeout, every call returned within the request timeout, and no transaction was left open. Its two timeout clauses could not fail, since a call whose lock wait hits the lock timeout, or that runs past the request timeout, ends the run before results are written. The doc points at the waiting-tasks table and the worst-case line for how long anyone waited, and says no writer-wait limit is set (#5940).
