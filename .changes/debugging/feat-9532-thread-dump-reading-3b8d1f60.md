---
bump: minor
---

### Added

- `/debugging:analyze-profile` reads a thread dump (py-spy dump text) directly, with no SQLite step, from the new `reference/formats/thread-dump.md` page: it starts at threads stopped in the same frame, lock waits and the main thread, and is done when each waiting thread is named with what it waits on at file:line. With no artifact in hand it now names `--kind threads` among the drive capture kinds.
- An eval case, in the skill's `evals.json` and as a plugin eval case with judge samples, that reads a real py-spy dump of a deadlocked script and names both blocked threads at file:line.
