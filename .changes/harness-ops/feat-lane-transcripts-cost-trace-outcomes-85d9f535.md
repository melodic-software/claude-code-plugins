---
bump: minor
---

### Added

- `observability`: `otel/lane-runs.sql` adds the DuckDB views `lane_runs` and `lane_outcomes` over the CI lane transcript sink, joined on `trace_id`, with the cache tokens, the CLI cost estimate and the failure class per lane leg; the read-routing, data-sources and query catalog rows point at them.
