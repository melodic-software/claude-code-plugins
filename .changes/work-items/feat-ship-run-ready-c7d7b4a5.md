---
bump: minor
---

### Changed

- `/work-items:ship run` under `per-item PRs` dispatches `/source-control:pull-request ready` into the item's worktree right after `create --pushed`, so its pull requests leave draft once that action's checks pass. A refusal (a hold, a superseded item, a failed gate) leaves the draft and is reported.
