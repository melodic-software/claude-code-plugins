# Changelog

All notable changes to the `desktop-notification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Master toggle and per-channel mutes migrated to native `userConfig`** (the
  fleet-wide kill-switch doctrine ruling). The whole-hook switch is now the
  `desktop_notification_enabled` boolean and each channel its own
  `desktop_notification_<channel>_enabled` boolean (default `true`), read by the
  hook through the native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process mirror.
  Configure interactively with `/plugin configure desktop-notification` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_DESKTOP_NOTIFICATION_*` environment variables are
  retired and no longer read. A consumer that set any of
  these in a settings `env` block must re-express the value as the matching
  `userConfig` option. Zero-config behavior is unchanged (all channels on, same
  defaults). The `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
