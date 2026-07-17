# Changelog

All notable changes to the `bash-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Breaking:** renamed the plugin `bash-lint` → `bash-format`, aligning with the hook-plugin
  `<tool>-format` verb family (`biome-format`, `ruff-format`, `powershell-format`) — the hook
  mutates files via shfmt, which "lint" undersold. This is a hard break with no marketplace
  `renames` entry: uninstall `bash-lint` and run `/plugin install bash-format@<marketplace>`.
  Renamed with it: the hook script (`hooks/bash-format.sh`), the telemetry `hook` value
  (`bash-lint` → `bash-format`), and the kill switch (`HOOK_BASH_LINT_ENABLED` →
  `HOOK_BASH_FORMAT_ENABLED` — re-set any disable override under the new name).
