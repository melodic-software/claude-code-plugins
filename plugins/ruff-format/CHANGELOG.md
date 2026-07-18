# Changelog

All notable changes to the `ruff-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The toggle is now the `ruff_format_enabled` boolean (default `true`), read by
  the hook through the native `CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED` hook-process
  mirror; the stdin read bound is the new `stdin_read_timeout` option (default `2`).
  Configure interactively with `/plugin configure ruff-format` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_RUFF_FORMAT_ENABLED` and `HOOK_STDIN_READ_TIMEOUT` environment
  variables are retired and no longer read. A consumer that set either in a settings
  `env` block must re-express the value as the matching `userConfig` option. Zero-config
  behavior is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK` consumer-side
  telemetry seam is unaffected.
