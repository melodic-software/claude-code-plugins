---
bump: patch
---

### Fixed

- worktree cleanup no longer says the session carries on from a directory that still exists after it removes its own worktree; since Claude Code 2.1.325 the next shell command fails and is re-issued with `git -C` or an absolute path (#16035).
