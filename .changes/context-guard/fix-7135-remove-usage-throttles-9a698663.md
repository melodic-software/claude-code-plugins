---
bump: major
---

### Removed

- **Breaking:** the blocking gate is gone. The `zone_hook_mode`, `zone_gate_grace_calls` and `zone_block_unattended` options are removed, a `block` action in `zones.json` reads as `none` (a `block` threshold keeps its boundary lines), and no zone denies a tool call. The status tool drops its `gate` field, `/context-guard` no longer prints a gate mode, and the `zone-gate` telemetry record is retired (#7135).

### Changed

- **Breaking:** `model_notices` replaces `zone_lines_enabled` and is off by default. Off, nothing from this plugin enters Claude's context; the toast, transcript line, band row, status tool, snapshot and PostCompact marker work as before. Set `model_notices` to `true` for the zone lines and options line; a stored `zone_lines_enabled: true` no longer applies (#7135).

### Added

- The snapshot file now publishes `zone`, `evidence_degraded` and `bands` (the edges in force after `zones.json`), so a status line can show the zone without importing plugin code. The README's "Published zone for status lines" and the reader contract document the shape (#7135).
