---
bump: patch
---

### Fixed

- `/machine-health:audit` names its reference files and per-OS orchestrators by their `${CLAUDE_PLUGIN_ROOT}/skills/audit/` path, reads them with the `Read` tool, runs `uname -s` as its own Bash call, and never lists the plugin directory or reads its files through Bash, Glob or Grep ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
