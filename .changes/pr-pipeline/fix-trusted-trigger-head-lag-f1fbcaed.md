---
bump: patch
---

### Fixed

- `check-trusted-trigger` re-reads a `workflow_dispatch` PR until `GET /pulls` shows the head its branch ref points at, waiting 5, 10, 20 and 25 s (60 s in all), so a job after pr-unblock's model job gates the head that job just pushed instead of the one `/pulls` still reports. When the two never agree, or the branch ref is missing, the lane stops with the new reason `head-lag` instead of gating a stale head; a fork is not waited on. `check-signed-commits` now uses the same read from `check-trusted-trigger`.
