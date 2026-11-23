---
bump: patch
---

### Changed

- In a sandboxed git session, `/source-control:worktree create` uses `EnterWorktree(name:)` with the create hook's `fresh` base for new branches. It stops when the session needs `worktree.baseRef: head`. Cleanup runs the stranded-work and carried-file guards before removing the session's own worktree with `ExitWorktree` and leaves lock ownership to the remove hook. The skill links to the live Claude Code docs for native placement and removal behavior.
