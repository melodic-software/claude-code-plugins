---
bump: patch
---

### Fixed

- Shared interview text fields, the heartbeat's question, a problem report's page errors and the page's client-log entries drop the characters that hide or reorder text: control and format characters (bidi controls, zero-width spaces, the soft hyphen, tags outside the England, Scotland and Wales flags), surrogates, private-use characters, characters that render blank, and variation selectors past VS16. Emoji sequences keep their single joiners and selectors, tabs and line breaks stay, and a field holding only hidden characters is refused as empty. A lone surrogate no longer fails the state write.
- Names are compared by their NFKC form, so a fullwidth or soft-hyphenated "Claude" is refused and a fullwidth form of a taken name gets a number; the name is stored as typed, less its hidden characters.
- A guest key holding a lone surrogate is refused as a wrong key instead of failing the join with a server error.
- Reloading the shared page no longer draws a 429 on its first heartbeat: a too-soon beat that changes nothing is answered without being recorded, and a tab may make two visibility changes a second.
- `share.py` writes its output and errors as UTF-8, so an emoji or arrow in a name or log line no longer crashes a Windows pipe.
- The shared-page snapshot map is tracked at `plugins/planning/shared/snapshot-map.md`, where `core.js` and the server tests cite it.
