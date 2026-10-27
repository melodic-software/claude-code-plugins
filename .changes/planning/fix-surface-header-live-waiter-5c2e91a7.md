---
bump: patch
---

### Fixed

- Interview surface: the header now turns Live as soon as a watcher starts waiting, and leaves Live when the wait ends, even within 10 seconds of the previous wait. Before, the open page heard of a new wait only when some other change came along, so it could read Claude is working while a watcher was waiting.
