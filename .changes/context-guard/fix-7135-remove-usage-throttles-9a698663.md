---
bump: major
---

### Removed

- **Breaking:** the blocking gate is gone. The `zone_hook_mode`, `zone_gate_grace_calls` and `zone_block_unattended` options are removed, a `block` action in `zones.json` (zone or threshold) is ignored, and no zone denies a tool call. The status tool drops its `gate` field, `/context-guard` no longer prints a gate mode, and the `zone-gate` telemetry record is retired (#7135).

### Changed

- **Breaking:** `model_notices` replaces `zone_lines_enabled` and is off by default. Off, nothing from this plugin enters Claude's context; the toast, transcript line, band row, status tool, snapshot and PostCompact marker work as before. Set `model_notices` to `true` for the zone lines and options line (#7135).
