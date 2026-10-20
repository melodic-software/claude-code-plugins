---
bump: minor
---

### Changed

- `/harness-ops:plugins sync` and `audit` now split the `Divergences:` count by what can be done about each part: actionable here, actionable elsewhere on the machine, in linked worktrees, and blocked (path not present). Only the actionable parts point at `converge`; the worktree part points at `/source-control:worktree audit` (if installed), and the blocked part points at the stale-records note. The digest's `divergences` object carries the new `actionable_here`, `actionable_elsewhere`, `in_worktrees` and `blocked` counts; `divergences[]` is not filtered, and a digest written before the split renders as it did.
