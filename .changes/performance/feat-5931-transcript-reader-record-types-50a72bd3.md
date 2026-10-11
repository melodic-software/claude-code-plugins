---
bump: patch
---

### Changed

- The shared transcript reader copy recognizes the eleven record types current Claude Code versions write (`ai-title` plus ten listed in `IGNORED_RECORD_TYPES`), so its `unknown` count no longer includes them.
