---
bump: patch
---

### Fixed

- check-wip-cap keeps the last known WIP and held-cap pause when the open listing or the base
  config cannot be read, instead of failing open. work-unblock's hourly sweep saves the
  status to the Actions cache; work-resolve-issue's pick-slot only restores it
  (`cache-mode: read`). With no saved state the check still fails open. A kept pause logs
  `admission paused: reason=<reason> (read-error, kept last state)`, and the status gains
  `pause_basis` (`read`, `last-state` or `fail-open`).
