---
bump: minor
---

### Added

- The control-skill contract gains "The launch model": `## Launch` starts the app from empty data,
  with migrations and seed, in a per-run data directory where the app keeps data, and records a
  `Data:` line, a `Side by side:` line saying whether two instances can run at once, and for a
  short-lived command-line or terminal app a `Session:` line (build once, one isolated session per
  drive). Every value is the consumer's.
- Ready now shows the instance is usable: the port or socket it reaches belongs to this run's
  instance and the credentials the run uses are valid, with `<check>: not exposed` where the app
  gives no way to check.
- `/app-control:map check` reports a hub whose `## Launch` has no `Data:` or `Side by side:` line
  under the new `launch-model` rule, and refresh treats that as doc drift, so existing control
  skills pick the lines up at their next refresh.

### Changed

- `/app-control:map` discovery asks where the app keeps data, its migrations and seed, whether two
  instances can run side by side and how to check port ownership and credentials; create's proof
  launches from empty state; `/app-control:drive`'s Ready rule names port ownership and credential
  validity.
- `/app-control:drive` reuses a running app only when it is the instance in this run's own launch
  record; any other running app is reached only through `--attach`.
