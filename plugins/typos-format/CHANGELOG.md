# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- Initial release. `PostToolUse` hook on `Write|Edit` runs `typos --force-exclude -w
  --format json` against the edited file (no extension filter — `typos` is a
  cross-language spell checker), auto-fixing every unambiguous typo and surfacing residual
  (ambiguous) findings via `additionalContext`, always advisory (exit `0`).
- Zero-config by design: ships no rules of its own, and discovers the consuming repo's
  optional `_typos.toml` (or `typos.toml`/`.typos.toml`/a `[tool.typos]`/
  `[workspace.metadata.typos]`/`[package.metadata.typos]` section) the same way `typos`
  itself does — anchored on the edited file, not this hook's working directory.
- `typos_format_enabled` `userConfig` kill switch (default `true`), read through the
  native `CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED` hook-process mirror.
- Missing `jq` or `typos` degrades to a visible once-per-session skip notice on both the
  agent (`additionalContext`) and user (`systemMessage`) channels; never a silent no-op.
- Hook-telemetry envelope (`hook: "typos-format"`) emitted opt-in via `HOOK_TELEMETRY_SINK`,
  gated so the unwired default path spawns zero telemetry-only subprocesses.
- `/typos-format:setup` skill on the uniform check-centric contract (`check` read-only,
  `apply` guidance-only — every prerequisite is a `PATH` binary or the native toggle, so
  there is no write path).
