---
bump: patch
---

### Fixed

- `/performance:go-faster` no longer reports the `hooks` area as `no-data` on a machine without hook telemetry when this session's transcript holds Stop hook timings. A new `findings.py stop-hook-timing` reads only the transcript's `stop_hook_summary` records and prints per-hook Stop p50 and p95. The record carries no async flag and the hooks configuration is not read, so the ranking covers only hooks with a recorded duration, assumed to block the turn's end; hooks with no recorded duration are listed apart, never ranked, and reported as assumed background and not confirmed.
