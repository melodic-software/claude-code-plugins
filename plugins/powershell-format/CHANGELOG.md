# Changelog

All notable changes to the `powershell-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Changed

- **Missing jq now skips visibly** (prerequisite-visibility wave; doctrine: a
  silently skipped feature is a defect). Without `jq` the hook cannot parse its
  input, so it now surfaces a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`) instead of a silent
  no-op. `pwsh`/PSScriptAnalyzer absence deliberately stays quiet — a machine
  without PowerShell is classified as not-applicable, and the README now says
  so. Notice dedup state lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The hook toggle is now the `powershell_format_enabled` option (default `true`),
  read by the hook through the native `CLAUDE_PLUGIN_OPTION_POWERSHELL_FORMAT_ENABLED`
  hook-process mirror. Configure interactively with `/plugin configure powershell-format`
  or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_POWERSHELL_FORMAT_ENABLED` environment variable is
  retired and no longer read. A consumer that set it in a settings `env` block
  must re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK`
  consumer-side telemetry seam is unaffected.
