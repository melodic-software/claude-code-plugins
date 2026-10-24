---
bump: minor
---

### Added

- The control-skill contract gains a "Steps files" section: a feature may keep its Drive steps in a machine-readable file whose format stays the project's choice. Step ids are unique after includes expand, and a repeated id stops the run before anything starts. An include can carry `prefix` (one file included twice with unique ids), `with` (parameter values for that include only; an undeclared name stops the run), `kind` (added to every included step, never removed) and `finally` (steps that run after a failure, where a write's reset goes). An optional step whose target is absent is recorded as skipped, with no retry or wait.
- `/app-control:drive` reads a feature's steps file as data: it expands includes and checks ids before launching, reports each step by id, records an absent optional step as `skipped: optional`, and runs finally steps after a failure. Each such step in `report.json` carries its `id`, an `outcome` and, for a finally step, `finally: true`.
