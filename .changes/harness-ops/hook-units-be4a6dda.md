---
bump: major
---

### Removed

- The session hooks and their options leave harness-ops. The `*-audit` rows, the telemetry sink, the per-session hook event log and their options are now the `session-telemetry` plugin (off by default); the hook-failure audit and the session-start node and prerequisites notices are the `plugin-diagnostics` plugin (on by default). Enable `session-telemetry@<marketplace>` and set its options again to keep recording; `HOOK_TELEMETRY_SINK=@harness-ops` keeps working through it.

### Changed

- `/harness-ops:observability`, `/harness-ops:audit-skill-visibility` and `/harness-ops:setup` read session-telemetry's records and options through `scripts/session-telemetry-state.mjs`. When session-telemetry is not enabled they say so, print the install and enable commands, and report what earlier sessions recorded.
- `/harness-ops:audit-skill-visibility` and its `skill-pair-cooccurrence.sh` read `skill-usage.jsonl.1` before `skill-usage.jsonl`, so usage counts and co-occurrence keep the history a size-capped store rotated out.
