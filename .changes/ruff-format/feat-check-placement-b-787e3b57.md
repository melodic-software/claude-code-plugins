---
bump: patch
---

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`.
- Vendored the shared git-hook installer and check lib under `lib/git-hooks/`; nothing uses them until this plugin ships its own git-hook entries.
