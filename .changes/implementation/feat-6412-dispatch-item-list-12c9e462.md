---
bump: minor
---

### Added

- **`/implementation:implement-dispatch` runs a spec'd list of work items with no PLAN.md.** `--items <path>` takes a list whose entries carry targets and acceptance checks, dispatches the ready items in waves in dependency order (tracker blocked-by edges read through the tracker seam, edges the list declares, and shared targets) instead of plan-phase order, verifies each item against its own acceptance checks, and returns the held items with what blocks each. `--base <ref>` sets the ref every worker worktree is cut from and checked against before the first edit, such as an integration branch; without it the base stays the default branch. The worker agents' base check compares against the base the brief names.
