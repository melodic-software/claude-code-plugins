---
bump: patch
---

### Fixed

- `/improvement:setup` looks up the user-global `~/.claude/improvement.md` with one Read of that literal path, never a Glob, a spelled-out home directory or a search of the home tree (#13768).
