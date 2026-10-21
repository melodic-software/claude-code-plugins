---
bump: minor
---

### Fixed

- On the shared interview page, a stale page's attachment chip x no longer takes a just-sent file off the post that carries it: the chip asks to remove only a draft, and the server refuses once the file is carried (#8615).
- A chat reaction chip keeps one label whether or not you reacted; its pressed state says which, as the WAI-ARIA toggle-button pattern asks.
