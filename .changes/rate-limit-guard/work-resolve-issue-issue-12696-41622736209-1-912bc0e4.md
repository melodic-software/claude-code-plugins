---
bump: patch
---

### Changed

- The README and reader contract no longer restate upstream behavior: what `--settings` can set, where mods can start processes, when an installed plugin loads, what `plugin install --config` and an uninstall do, and what upstream promises about `.oauthAccount` in `~/.claude.json` ([#12696](https://github.com/melodic-software/claude-code-plugins/issues/12696)). The guidance stays, and each item now points at the upstream section, or for `oauthAccount` cites the dated local observation of the key.
