---
bump: patch
---

### Fixed

- `measure-hook-log-budget.sh` waits on each parallel hook row and append job by pid and exits 3 when one fails, instead of timing a failed run into `parallel_wall_*` or reporting a short append line count.
