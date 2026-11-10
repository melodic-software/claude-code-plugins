---
bump: minor
---

### Added

- `limits.sweep-gap-minutes` (default 15). A work-unblock sweep that a finished work-resolve-issue run starts skips its work, and requests no lane token, when a full sweep (a run that uploaded `work-unblock-verdicts`, whatever it concluded) finished under this many minutes ago. A scheduled sweep or an issue close never skips, and a read that fails runs the sweep. 0 turns the gap off.
