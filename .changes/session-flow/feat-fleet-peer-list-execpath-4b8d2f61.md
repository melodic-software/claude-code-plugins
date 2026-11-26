---
bump: patch
---

### Changed

- The shared `session-attended.env`, `session-attended.sh` and `session-attended.mjs` copies gain a reader for `CLAUDE_CODE_EXECPATH`, which the fleet peer list uses; the attended predicate and session-flow's behavior do not change.
