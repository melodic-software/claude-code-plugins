---
bump: minor
---

### Changed

- `limits.sweep-gap-minutes` is 5 instead of 15, so the work-unblock sweep a finished work-resolve-issue run starts fills the freed slot at once unless a full sweep finished in the last 5 minutes. Against the 15-minute schedule, 15 skipped 12 of 21 such sweeps; a full sweep now spends at most 109 lanes App calls, not the 800 the old value was sized on. The README's basis for both sweep limits states the measurement; `restarts-per-run` stays 10, since it never deferred a restart in 69 full sweeps.
