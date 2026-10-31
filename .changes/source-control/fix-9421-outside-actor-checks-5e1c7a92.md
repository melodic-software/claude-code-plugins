---
bump: patch
---

### Security

- `resolve-version-bump-conflict.sh` leaves a plugin for manual resolution when its `CHANGELOG.md` or `plugin.json` is a symlink, instead of writing through the link.
