---
bump: minor
---

### Added

- `/harness-ops:observability hooks <transcript>` reads per-hook durations the harness recorded in a session transcript (Stop `stop_hook_summary` records, sampled `hook_success` and `hook_non_blocking_error` attachments): median per hook, the slowest hook per event, and enabled hooks with no sample from an operator-supplied `--enabled` list. It executes no hook and never prints hook output.
- `/harness-ops:observability latency --transcript <path>` falls back to that transcript when duckdb or the OTEL store is missing: lane `unknown`, sampled events with no budget flag or slope.

### Changed

- `/harness-ops:audit-performance`: the "Never time a hook by running it" gotcha also names the per-hook attachment records and gives a filter that extracts their timing fields alone.
