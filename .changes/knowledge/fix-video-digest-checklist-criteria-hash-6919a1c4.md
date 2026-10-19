---
bump: patch
---

### Fixed

- `video-digest` `init-watch-checklist.js --force` now drops a tick, with its evidence lines, when the row's criteria text changed since it was ticked, and prints the dropped row ids on stdout. Each checklist row carries a criteria hash for this; a tick saved before the hash existed is kept and gets the current hash stamped.
