---
bump: patch
---

### Changed

- Shared `install.mjs` synced where this plugin carries it: the vendored git-hook installer gains
  a `config-hook` action for `commit-msg` entries, which this plugin has none of; its own entries
  install and verify as before
  ([#9775](https://github.com/melodic-software/claude-code-plugins/issues/9775)).
