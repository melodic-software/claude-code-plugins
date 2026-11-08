---
bump: minor
---

### Added

- `HOOK_TELEMETRY_SINK=@harness-ops` sends the mod's `zone-crossing-inject` envelopes to the launcher harness-ops keeps in its plugin data directory, found under `CLAUDE_CONFIG_DIR` or `~/.claude` (#14227). With no launcher installed the envelope is skipped. Any other value starting with `@` is reserved and skipped, never joined onto the project root.

### Changed

- Shared `hook-utils.sh` synced: `hook::emit_telemetry` resolves the same reserved value for `post-compact-mark`.
