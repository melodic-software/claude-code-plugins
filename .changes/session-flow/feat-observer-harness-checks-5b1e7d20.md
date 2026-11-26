---
bump: minor
---

### Added

- With `observer_harness_check` on, the observer runs scripted harness checks that call no model: a hook whose p95 latency this session passes `observer_hook_p95_ms` (read from session-telemetry's per-session hook log), a turn that rewrites the prompt cache with no break, compaction or model switch to explain it, a tool or Bash command that runs past `observer_tool_slow_seconds` `observer_tool_repeat` times, each crossing of `observer_context_percents`, and a rate-limit window at `observer_rate_limit_percent`. Each finding lands in the running-retro ledger and the band under a `harness` category, names its fix (here in this session, or a ready `cd <repo>` and `claude -n <name> "<prompt>"` command for a dedicated session on this platform), and `/observer` counts them beside the live checks. A dedicated-session finding is never auto-sent. Off by default.
