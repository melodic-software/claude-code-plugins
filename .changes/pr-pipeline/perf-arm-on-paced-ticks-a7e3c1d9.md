---
bump: minor
---

### Changed

- pr-merge's enable-auto-merge job runs on a paced schedule tick too; only the merge sweep job still skips a tick the burn-rate pacer paces (owner decision, 2026-11-22). A PR-scoped arm defers in the same tight windows the pacer paces, so on 2026-11-21 no sweep armed a green PR for 450 minutes in 16 gaps (longest 54). Arming on paced ticks bounds a gap at one tick, about 195 minutes a day replayed, for about 35 calls a paced tick.
