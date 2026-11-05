---
bump: patch
---

### Fixed

- `/developer-experience:build-cli` names its CLI contract by its `${CLAUDE_PLUGIN_ROOT}/skills/build-cli/` path, opens plugin files with the `Read` tool and never Globs or Greps the plugin directory, and prints the install line with `<marketplace>` left as written ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
