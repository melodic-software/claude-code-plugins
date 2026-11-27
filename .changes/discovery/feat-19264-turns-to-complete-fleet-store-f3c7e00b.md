---
bump: minor
---

### Changed

- `scripts/turns-to-complete.py` reads per-dispatch turn rows across every collected fleet source through `session-flow`'s `scripts/dispatches.py` when `session-flow` is installed and has a store, falling back to local sources when `session-flow` or its store is absent, with the report header naming which source was read.
