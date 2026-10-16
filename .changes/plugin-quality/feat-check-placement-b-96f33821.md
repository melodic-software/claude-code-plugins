---
bump: patch
---

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.
- The evidence-packet reference and `packet-seal.sh` no longer cite `typos-format` as a formatter that rewrites packet files in session; `markdown-format` remains the example, since typos-format now reports at commit time.
