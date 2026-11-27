---
bump: patch
---

### Fixed

- `/source-control:worktree create` and entering an existing worktree now work by explicit path, with no `EnterWorktree` call, when the worktree root is one of the session's working directories, so the person is not asked to approve a move the session does not need. A session that cannot reach the root still enters with `EnterWorktree(path:)`.
