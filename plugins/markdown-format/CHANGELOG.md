# Changelog

All notable changes to the `markdown-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Changed

- **Missing-prerequisite notices now reach the user too, once per session**
  (prerequisite-visibility wave). The jq and markdownlint-cli2 absence
  warnings — previously an `additionalContext`-only message repeated on every
  edit — now use the shared visible-skip mechanism: one notice per session on
  both channels (`additionalContext` for Claude, `systemMessage` for the
  user). Notice dedup state lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).

## [0.3.0]

### Changed

- **Kill switch migrated to native `userConfig`.** The toggle is now the
  `markdown_format_enabled` boolean (default `true`), read by the hook through the
  native `CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED` hook-process mirror. Configure
  interactively with `/plugin configure markdown-format` or headless via
  `claude plugin install --config KEY=VALUE`.

### Breaking

- The `HOOK_MARKDOWN_FORMAT_ENABLED` environment variable is retired and no longer
  read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option. Zero-config behavior is
  unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK` telemetry seam is unaffected.

## [0.2.0]

### Changed

- **Breaking:** renamed the plugin `markdown-formatter` → `markdown-format`, aligning with the
  hook-plugin `<tool>-format` verb family (`biome-format`, `ruff-format`, `powershell-format`).
  This is a hard break with no marketplace `renames` entry: uninstall `markdown-formatter` and
  run `/plugin install markdown-format@<marketplace>`. Skills, hook behavior, telemetry `hook`
  value (`markdown-format`), and the `HOOK_MARKDOWN_FORMAT_ENABLED` kill switch are unchanged.
