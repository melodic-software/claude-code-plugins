# Changelog

All notable changes to the `desktop-notification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/desktop-notification:setup
  check` reads the hook scripts as the single source of truth and probes Bash version, `jq`,
  and — for the current OS only — the `os_toast` channel dependency (Linux `notify-send`;
  macOS built-in `osascript`; Windows terminal-only), then reports the four channel toggles'
  effective values. `apply` is guidance-and-verify with no write path: it points at the
  README install steps and `/plugin configure` for a muted toggle, installs nothing, and
  re-runs the probe after any system-tool remediation.

## [0.3.2]

### Changed

- **Freshness rider on the channel table** (fleet conformance wave). The
  `terminalSequence` / Claude Code v2.1.141+ claim is re-verified against the
  Claude Code changelog and dated, with links to the changelog and the hooks
  reference.

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

## [0.3.0]

### Changed

- **Missing jq now skips visibly** (prerequisite-visibility wave; doctrine: a
  silently skipped feature is a defect). Without `jq` the hook can neither
  classify the notification nor emit its terminal sequence, so it now surfaces
  a once-per-session `systemMessage` notice (the Notification event has no
  `additionalContext` channel) instead of silently dropping every
  notification. Notice dedup state lives under
  `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now states the jq absence behavior and the Bash (Git Bash on native
  Windows) hook runtime.

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
