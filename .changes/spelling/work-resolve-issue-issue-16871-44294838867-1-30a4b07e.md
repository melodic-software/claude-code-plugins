---
bump: patch
---

### Changed

- `setup` `check` gives the reason it opens plugin files by path and never runs Glob or Grep over the plugin directory: a search passed the installed plugin's deeply nested cache path can fail to start on some hosts because the path is too long ([#16871](https://github.com/melodic-software/claude-code-plugins/issues/16871)).
