---
bump: patch
---

### Fixed

- `/context-budget:audit` names its `reference/...` files by their `${CLAUDE_PLUGIN_ROOT}/skills/audit/` path and reads them with the `Read` tool, never through Bash, Glob or Grep, and runs `lib/state-key.sh` as its own Bash call with nothing chained to it ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
