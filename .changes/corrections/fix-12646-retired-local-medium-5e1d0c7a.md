---
bump: patch
---

### Changed

- Shared `config-cascade.mjs` synced where this plugin carries it ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)): it exports the scan that finds a `yaml config` block in a team Markdown file, returning the block's body; resolution is unchanged and there is no other change to this plugin.
