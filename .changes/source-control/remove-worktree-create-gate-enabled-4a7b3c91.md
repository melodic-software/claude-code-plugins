---
bump: major
---

### Removed

- The `worktree_create_gate_enabled` option. Its only off position made the WorktreeCreate gate refuse, so every harness-driven worktree creation failed. The gate now always runs; a stored `false` is ignored. To stop the gate placing worktrees, disable the plugin.
