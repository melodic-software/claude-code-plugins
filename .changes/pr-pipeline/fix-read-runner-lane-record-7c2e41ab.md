---
bump: patch
---

### Fixed

- `pr-run-activity-read.yml` passes turns, max turns, models and profile to `report-check-run`, as
  the write runner does. A read activity that ended well has no failure class, so it posted no lane
  record at all, and its check run could not be read for turns or models.
