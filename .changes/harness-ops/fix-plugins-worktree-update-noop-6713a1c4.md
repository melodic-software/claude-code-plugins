---
bump: patch
---

### Fixed

- `/harness-ops:plugins` no longer reports a no-op update as a success. `fleet-state.sh` marks each project or local record `linkedWorktree` and labels a lagging one in a linked git worktree `update ineffective; uninstall clears it`, keeping it in the divergence count. `sync` reports an "already at the latest version" update whose project record is still below the catalog as a failed row. `converge` offers linked-worktree rows only the uninstall strategy and counts an update whose re-read record did not move as a failure.
