---
bump: patch
---

### Fixed

- The session-start hook writes `~/.claude/plugin-profiles-state/root` only from the copy that `plugins/installed_plugins.json` records as this plugin's user-scope install, so a running session whose hooks load an older cached version no longer points the `claude` shell function back at that old code. A missing or unreadable record writes nothing.
