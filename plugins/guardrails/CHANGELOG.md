# Changelog

All notable changes to the `guardrails` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Changed

- **Per-hook kill switches and tuning scalars migrated to native `userConfig`** (the
  fleet-wide kill-switch doctrine ruling). Each guard's toggle is now a `userConfig`
  boolean named `<guard>_enabled` (default `true`), read by the hooks through the
  native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror; `cli-flag-verify`'s binary
  set and skip list are now the `cli_flag_verify_bins` / `cli_flag_verify_skip_bins`
  options. Configure interactively with `/plugin configure guardrails` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_<NAME>_ENABLED`, `HOOK_CLI_FLAG_VERIFY_BINS`, and
  `HOOK_CLI_FLAG_VERIFY_SKIP_BINS` environment variables are retired and no
  longer read. A consumer that set any of these in a
  settings `env` block must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (all guards on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
