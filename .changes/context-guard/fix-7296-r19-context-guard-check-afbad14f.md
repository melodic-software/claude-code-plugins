---
bump: patch
---

### Fixed

- `/context-guard:setup check` reads this session's snapshot file with the `Read` tool, opens plugin files only by their `${CLAUDE_PLUGIN_ROOT}` paths without Glob or Grep of the plugin directory, and names the snapshot directory's permissions as the operator's next check instead of write-probing it ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
