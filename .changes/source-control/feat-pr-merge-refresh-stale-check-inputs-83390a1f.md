---
bump: minor
---

### Added

- The unattended merge gate updates a ready pull request from its base (`update-branch`, a merge)
  instead of enqueuing it when the base changed a `merge.check-inputs` path since the pull
  request's merge base, and enqueues the new head on a later run once its checks pass. The answer
  comes from the local clone of the base, with no API read. The shared-copy registry counts only
  for a pull request touching a path it registers. Any doubt, a refused update (its status and
  message recorded as `updateError`), or a Dependabot head enqueues as before.
