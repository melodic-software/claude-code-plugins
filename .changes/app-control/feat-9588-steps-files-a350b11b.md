---
bump: minor
---

### Added

- The control-skill contract gains a "Steps files" section: a feature may keep its Drive steps in a machine-readable file whose format stays the project's choice. Step ids are unique after includes expand and use letters, digits, `-` and `_` only; a repeated or malformed id stops the run before anything starts. Includes stay inside the control skill's own directory. An include can carry `prefix` (one file included twice with unique ids), `with` (parameter values for that include only; an undeclared name stops the run), `kind` (added to every included step, never removed) and `finally` (steps that run after a failure, where a write's reset goes). An optional step whose target is absent is recorded as skipped, with no retry or wait.
- `/app-control:drive` reads a feature's steps file as data: it expands includes and checks ids before launching, reports each step by id, records an absent optional step as `skipped: optional`, and runs the finally steps after the others, failed or not. Each such step in `report.json` carries its `id`, an `outcome` and, for a finally step, `finally: true`.

### Fixed

- `/app-control:drive` and `/app-control:map` name each reference file they send the model to by its full plugin path, so a run reads it directly and does not search the plugin directory for it.
