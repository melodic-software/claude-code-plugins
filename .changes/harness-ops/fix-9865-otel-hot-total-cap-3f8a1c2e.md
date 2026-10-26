---
bump: minor
---

### Added

- **`CC_OTEL_HOT_TOTAL_MAX_MB` caps the hot OTEL store files together.** Each prune now trims
  `cc-logs.json`, `cc-metrics.json` and `cc-traces.json` to at most 1024 MiB in total by default
  (`0` disables), dropping the oldest lines across all three to cold first. Before this, only the
  per-file `CC_OTEL_HOT_MAX_MB` cap applied, so three files each under it could together pass the
  1 GiB hot budget provisioning checks. `operator-setup-retention.md` documents the knob.

### Fixed

- **`CC_OTEL_HOT_MAX_MB` with a leading zero** (`08`) is read as base 10 instead of failing as octal.
