---
bump: patch
---

### Security

- `resolve-version-bump-conflict.sh` leaves a plugin for manual resolution when its `CHANGELOG.md` or `plugin.json` or the `.claude-plugin` directory is a symlink, whether the link resolves or not, instead of writing through it or skipping the plugin.
