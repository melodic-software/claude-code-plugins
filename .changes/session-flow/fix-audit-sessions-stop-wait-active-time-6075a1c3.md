---
bump: patch
---

### Fixed

- `audit-sessions` measures Stop-hook wait as the slowest hook per Stop run, not the sum of hooks that run in parallel, and active time from the gaps between a session's own records (each capped at 300 s), so a session never reports more active time than its wall clock and one without `turn_duration` records no longer reports 0.

### Changed

- The store gains `stop_hooks.wait_ms_total`, `wait_ms_p50`, `wait_ms_p90` and `time.active_gap_s`; the existing `ms_*` and `active_s` keys keep their meaning. The sweep's `hooks.stop_ms` and `time.active_s` read the new keys, are labeled heuristic, and have no threshold (report-only) until re-derived.
- The `turn_duration` canaries are replaced by a record-timestamp canary and two invariant canaries (`invariant:active_over_wall`, `invariant:stop_wait_over_sum`); SKILL.md records the direct-parsing decision with a pointer to the sessions page.
