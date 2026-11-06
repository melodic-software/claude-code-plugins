---
bump: patch
---

### Fixed

- `/codebase-health:audit` looks up the user-global `~/.claude/codebase-health.md` with one Read of that literal path, never a Glob, a spelled-out home directory or a search of the home tree; the rendered-view resolver command takes `--option "<option>"` instead of the `${user_config.medium}` token; and the rendered-views files are never read or audited in any phase (#7296).
