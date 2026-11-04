---
bump: patch
---

### Fixed

- `/source-control:babysit-prs` safety reference reads the Bash wrapper-strip list at its pointer instead of restating it, which had `xargs` wrong.
- `/source-control:worktree` no longer says project hooks do not run in a `claude -p` session as the reason its probe passes `--settings`.
