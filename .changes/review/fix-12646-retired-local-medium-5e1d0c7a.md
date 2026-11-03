---
bump: patch
---

### Fixed

- Shared `view-settings.mjs` synced where this plugin carries it ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)): a `terminal` or `file` value in a retired `rendered-views.md` file keeps the view local when no scope sets one, instead of falling to a publishing default; no other change to this plugin.
