---
bump: minor
---

### Added

- A repository routes its hook telemetry through this plugin's reference sink with no copy and no per-machine path: `"HOOK_TELEMETRY_SINK": "@harness-ops"` in its `settings.json` (#14227). A new SessionStart hook, `hooks/refresh-sink-launcher.sh`, keeps a launcher at `${CLAUDE_PLUGIN_DATA}/hook-telemetry-sink.sh`, rewritten only when the install's sink path or its `session_event_log_dir` or `hook_events_max_bytes` changes and touched otherwise, and every producer resolves the reserved value to the most recently refreshed launcher, so two installs (a `--plugin-dir` one and a marketplace one) never split rows across two roots. The launcher deletes itself when its install is gone.

### Changed

- The README documents `@harness-ops` as the default wiring, and the copy route now lists every file the sink needs: `hook-telemetry-sink.sh`, `hook-utils.sh` and `session-log-lib.sh`.
- Shared `hook-utils.sh` synced: `hook::emit_telemetry` resolves `@harness-ops` and skips any other value starting with `@`.

### Fixed

- The reference sink maps `subject` from `data.file` when the envelope has no `data.subject`, so rows from producers that build their data with `hook::data_json_to` (guardrails, the formatters) no longer land with an empty `subject`.
