---
bump: patch
---

### Changed

- `implement-dispatch`: every worker brief now carries a clause to wrap each command that can block in a timeout, record a timeout as a FAIL, and never run an interactive command. Observed once, while implementing #6306 (PR #6669): a Phase 1 worker hung 2.5 hours on one unbounded Sanity Check command and had to be stopped; later briefs carried the clause and no phase hung again.
