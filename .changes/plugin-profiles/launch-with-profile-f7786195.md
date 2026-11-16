---
bump: patch
---

### Fixed

- A new git worktree whose `.claude/settings.local.json` was copied from the main worktree now takes the main worktree's folder profile when the copy still holds every entry that profile wrote, so `status`, the session-start notice, `clear` and `launch` with no name see the profile there instead of reporting none.
