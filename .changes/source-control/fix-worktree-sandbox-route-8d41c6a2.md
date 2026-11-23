---
bump: patch
---

### Changed

- `/source-control:worktree` states a route for sandboxed sessions: inside a git repository, `create` uses `EnterWorktree(name:)` and removal of that worktree uses `ExitWorktree(action: "remove")` instead of Bash `git worktree add` and `remove`, which the sandbox refuses; outside a git repository it stops rather than falling back to Bash. Unsandboxed sessions keep the existing route.
