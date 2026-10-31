---
bump: minor
---

### Added

- The half-hourly tick now picks up a fix request on a lanes App pull request. The
  `pr-feedback-dispatch` sweep sends a head with an unresolved thread the reviewer bot opened whose
  newest fix request, by a trusted person with write access, is newer than the head's newest
  `pr-unblock / address-feedback` check run; check runs that started before it stop counting for
  that dispatch, and a limit stop keeps its reset hold. `SWEEP_HEAD_CAP` still bounds the head, and
  no trigger, workflow or trust check changes.
