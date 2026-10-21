---
bump: patch
---

### Fixed

- check-wip-cap keeps the last known WIP and held-cap pause when the open listing or the base
  config cannot be read, instead of failing open. The last run whose reads succeeded saves its
  status to the Actions cache; with no saved state the check still fails open. A kept pause logs
  `admission paused: reason=<reason> (read-error, kept last state)`, and the status gains
  `pause_basis` (`read`, `last-state` or `fail-open`).
