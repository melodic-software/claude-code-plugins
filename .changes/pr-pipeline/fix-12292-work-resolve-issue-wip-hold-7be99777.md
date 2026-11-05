---
bump: patch
---

### Fixed

- work-resolve-issue holds a run whose WIP cap check could not read the pause (a failed or incomplete open lane PR listing or base config read, or a check that failed or set nothing): resolve-issue starts only on `capped` `false`, pick-slot ends green with a `WIP cap hold` notice, and work-unblock's sweep re-fires the issue so its next run reads again. Before, a failed read kept the last pause work-unblock's hourly sweep had cached, and with none the run started. check-wip-cap no longer restores or saves that cache (`save-state` and `state-saved` are gone, `pause_basis` is `read` or `unknown`), and work-unblock's `wip-state` job, which only saved it, is removed.
