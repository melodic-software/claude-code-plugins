---
bump: patch
---

### Fixed

- The interview page header reads `Live` only while a watcher is waiting. While Claude holds the lease or the bridge reports the session reading, with no watcher waiting, it reads `Claude is working on <question>` instead of staying `Live` for the rest of the lease timeout. A delivery unhandled for ten minutes still reads `Not listening: type next`, lease or not. Chips and the receipt line are unchanged.
