---
bump: patch
---

### Fixed

- Shared interview text fields, the heartbeat's question and a problem report's page errors drop the characters that hide or reorder text: bidi controls, zero-width spaces, stray tag characters, other control characters, surrogates and private-use characters. Emoji sequences, tabs and line breaks stay, and a field holding only such characters is refused as empty. A lone surrogate no longer fails the state write.
- Reloading the shared page no longer draws a 429 on its first heartbeat: a too-soon beat that changes nothing is answered without being recorded, and a tab may make two visibility changes a second.
- `share.py` writes its output and errors as UTF-8, so an emoji or arrow in a name or log line no longer crashes a Windows pipe.
- The shared-page snapshot map is tracked at `plugins/planning/shared/snapshot-map.md`, where `core.js` and the server tests cite it.
