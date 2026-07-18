# Changelog

All notable changes to the `powershell-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The hook toggle is now the `powershell_format_enabled` option (default `true`),
  read by the hook through the native `CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED`
  hook-process mirror; the stdin read bound is the `stdin_read_timeout` option (default `2`).
  Configure interactively with `/plugin configure powershell-format` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_POWERSHELL_FORMAT_ENABLED` and `HOOK_STDIN_READ_TIMEOUT`
  environment variables are retired and no longer read. A consumer that set either in a
  settings `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK`
  consumer-side telemetry seam is unaffected.
