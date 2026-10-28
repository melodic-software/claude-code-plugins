---
bump: patch
---

### Changed

- `/work-items:work` now dispatches one PR owner as soon as `create --pushed` returns, without waiting on CI. The owner runs at the strong tier in the persisted worktree and runs both the monitor watch and the post-green review pass, so the separate monitor dispatch and its idle handoff are gone. The orchestrator waits on the owner with `run_in_background` or Monitor, never a poll loop. Fix workers are still fresh dispatches into the same worktree, and the never-merge boundary and the `/source-control:babysit-prs` handoff are unchanged.
