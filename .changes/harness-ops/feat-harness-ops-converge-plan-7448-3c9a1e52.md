---
bump: minor
---

### Added

- `plugins converge` has a planning script, `converge-plan.sh`. It reads the `fleet-state.sh` report and prints one row per lagging `(projectPath, id)` pin, grouped by path, with the strategy, the exact command, and a class: `actionable`, `worktree`, `blocked-absent`, `blocked-home` or `blocked-catalog`. A blocked row carries no command, and a linked-worktree row is offered uninstall only.

### Changed

- `plugins converge` Step 3 now confirms one batch per project path, with approve, other strategy or skip per row, instead of one prompt per plugin across the whole fleet. It still refuses a single approval that covers several paths. The committed-enable check that picks `update` over `uninstall` is now made by the script, not by the model reading each settings file.
