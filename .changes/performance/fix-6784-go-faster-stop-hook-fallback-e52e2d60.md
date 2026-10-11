---
bump: patch
---

### Fixed

- `/performance:go-faster` no longer reports the `hooks` area as `no-data` on a machine without hook telemetry when this session's transcript holds Stop hook timings. A new `findings.py stop-hook-timing` reads only the transcript's `stop_hook_summary` records and prints per-hook Stop p50 and p95; hooks with no recorded duration, such as background hooks, are listed apart and never ranked.
