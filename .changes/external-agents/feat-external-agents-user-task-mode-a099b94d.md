---
bump: minor
---

### Added

- add the `antigravity_uses_task_mode` userConfig option, so one per-user setting turns on
  Antigravity task writes in every repository and worktree

  It defaults to `read-only`, so nothing changes for a user who sets nothing. The command reads
  `pluginConfigs` from the user and managed settings itself and feeds the value to the config
  cascade's userConfig layer, which a repository's team or personal file still overrides. An
  unreadable settings file or managed-settings directory leaves the layer empty and prints a
  notice. The option's `options` picker needs Claude Code v2.1.271 or later.
