---
bump: patch
---

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`.
- Vendored the shared git-hook installer and check lib under `lib/git-hooks/`; nothing uses them until this plugin ships its own git-hook entries.
- The README's known-limitation note no longer names typos-format's removed write mode as the other in-place Markdown rewriter; it now covers any other hook that rewrites Markdown in place.
