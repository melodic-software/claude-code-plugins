---
bump: patch
---

### Changed

- The `setup` skill states the reason for three of its "never" rules: no `${user_config.*}` string in a shell command, no Glob or Grep over the plugin directory, and no competing lockfile ([#16878](https://github.com/melodic-software/claude-code-plugins/issues/16878)).
