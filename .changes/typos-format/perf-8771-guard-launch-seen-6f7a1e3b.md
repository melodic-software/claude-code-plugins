---
bump: patch
---

### Changed

- Shared `exec-bash.mjs` synced: `--skip-unless-marker` also skips when every `<session>.launched` it finds holds a launch token that `<session>.seen` beside it repeats. No hook in this plugin uses that flag; no other change to this plugin.
