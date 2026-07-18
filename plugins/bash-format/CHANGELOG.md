# Changelog

All notable changes to the `bash-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Changed

- **Kill switch migrated to native `userConfig`.** The bash-format toggle is now the
  `bash_format_enabled` option (default `true`), read by the hook through the native
  `CLAUDE_PLUGIN_OPTION_BASH_FORMAT_ENABLED` hook-process mirror; the stdin read bound is
  now the `stdin_read_timeout` option (default `2`). Configure interactively with
  `/plugin configure bash-format` or headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_BASH_FORMAT_ENABLED` and `HOOK_STDIN_READ_TIMEOUT` environment
  variables are retired and no longer read. A consumer that set either in a settings `env`
  block must re-express the value as the matching `userConfig` option. Zero-config behavior
  is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK` telemetry seam is
  unaffected.

## [0.2.0]

### Changed

- **Breaking:** renamed the plugin `bash-lint` → `bash-format`, aligning with the hook-plugin
  `<tool>-format` verb family (`biome-format`, `ruff-format`, `powershell-format`) — the hook
  mutates files via shfmt, which "lint" undersold. This is a hard break with no marketplace
  `renames` entry: uninstall `bash-lint` and run `/plugin install bash-format@<marketplace>`.
  Renamed with it: the hook script (`hooks/bash-format.sh`), the telemetry `hook` value
  (`bash-lint` → `bash-format`), and the kill switch (`HOOK_BASH_LINT_ENABLED` →
  `HOOK_BASH_FORMAT_ENABLED` — re-set any disable override under the new name).
