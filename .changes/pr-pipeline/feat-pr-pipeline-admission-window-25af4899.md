---
bump: minor
---

### Added

- `limits.admission-window-hours` (default 24): the hours of issue-lane admissions the admitted
  backlog (open issues labeled `agent-ready`) may hold before new `agent-ready` labels pause. This
  repository sets 24.
- `limits.admission-factor` (default 0.8, greater than 0 and at most 1): the share of the lane's
  hourly merge rate admitted per hour.
- `.github/scripts/work-resolve-issue/admission-window.mjs` reports whether admissions are open
  from live counts and exits 0 open, 1 held, 2 on error.
