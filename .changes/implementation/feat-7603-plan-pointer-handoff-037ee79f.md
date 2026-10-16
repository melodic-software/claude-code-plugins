---
bump: minor
---

### Changed

- `/implementation:implement` hands `/verification:confirm` the PLAN.md path at Step 5, and `/implementation:implement-dispatch` puts the PLAN.md's absolute path in each plan-driven worker brief (not under `--items` or holdout tests) and passes it on to Step 5, so a fresh session can read the Brief.
