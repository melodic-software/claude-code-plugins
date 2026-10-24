---
bump: patch
---

### Fixed

- `/source-control:worktree cleanup` now runs the workspace environment `down` command in a subshell, `(cd '<WORKSPACE_ROOT>' && env ... <down command>)`. The bare `cd` persisted between Bash calls and left the session inside the worktree it was about to remove, so the later `rmdir` failed with Device or resource busy.
