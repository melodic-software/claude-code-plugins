---
bump: patch
---

### Changed

- Shared `publish-gate.mjs` synced where this plugin carries it: the page stamp it removes before scanning now matches only the builders' own stamp names, so a token inside a look-alike comment is still found; no other change to this plugin.
