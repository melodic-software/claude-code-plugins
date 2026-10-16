---
bump: patch
---

### Changed

- `/work-items:work` and `/work-items:ship run` dispatch `/source-control:pull-request ready --unattended`, so `ready` never flips a draft a person asked for (a `Draft:` body line) from a lane or orchestrated run.
