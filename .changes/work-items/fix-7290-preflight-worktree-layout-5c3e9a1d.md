---
bump: patch
---

### Fixed

- The work preflight no longer credits the main checkout's `settings.local.json` to a worktree where Claude Code keeps approvals per worktree: on Windows, with the repository root equal to `$HOME` (symlinks resolved), or with a root not owned by the user, it credits only the worktree's own file. A layout it cannot determine (including an unreadable platform) is not credited and ends `PREFLIGHT: INCOMPLETE`.
