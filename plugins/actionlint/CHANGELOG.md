# Changelog

All notable changes to the `actionlint` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling). The hook toggle is now the `actionlint_enabled` boolean
  (default `true`), read by the hook through the native
  `CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED` hook-process mirror. Configure
  interactively with `/plugin configure actionlint` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_ACTIONLINT_ENABLED` environment variable is retired
  and no longer read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option. Zero-config behavior is unchanged (hook on, same
  defaults). The `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is
  unaffected.
