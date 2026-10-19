---
bump: patch
---

### Fixed

- `/source-control:worktree cleanup` runs both keep/remove guards before it stops any process. Step 4a is now guard 1 (stranded work), guard 2 (carried files, plus the `worktree-claim.sh stale` proof for a locked row), then the file-lock release, the Workspace `down`, the reap and the removal, and Step 4b emits the branch deletion. A row any guard keeps has no side effects: its build servers, daemons and MCP or surface servers keep running.
