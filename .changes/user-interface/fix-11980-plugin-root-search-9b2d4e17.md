---
bump: patch
---

### Fixed

- `/user-interface:design` says where its settings come from when detect cannot run (no shell, as
  in an eval run, or no `node`): `reference/defaults.yaml`. It reaches plugin files only by the
  paths it and `concerns.json` name and never searches the plugin's directory, which the eval
  sandbox denies. The animation catalog names both sources of its
  resolved `animation:` config, detect's `config.values.animation` and the defaults file. Eval
  runs had searched the plugin root for those values, and the sandbox's denials made both sides
  invalid ([#11980](https://github.com/melodic-software/claude-code-plugins/issues/11980)).
