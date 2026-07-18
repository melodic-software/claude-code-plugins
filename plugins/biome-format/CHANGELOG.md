# Changelog

All notable changes to the `biome-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling). The hook's toggle is now the `biome_format_enabled` boolean
  (default `true`), read through the native `CLAUDE_PLUGIN_OPTION_<KEY>`
  hook-process mirror; the stdin read bound is the `stdin_read_timeout` option
  (default `2`). Configure interactively with `/plugin configure biome-format` or
  headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_BIOME_FORMAT_ENABLED` and `HOOK_STDIN_READ_TIMEOUT`
  environment variables are retired and no longer read. A consumer that set
  either in a settings `env` block must re-express the value as the matching
  `userConfig` option. Zero-config behavior is unchanged (hook on, same
  defaults). The `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is
  unaffected.
