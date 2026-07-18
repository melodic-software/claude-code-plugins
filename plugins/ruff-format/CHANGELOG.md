# Changelog

All notable changes to the `ruff-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Changed

- **Missing prerequisites now skip visibly** (prerequisite-visibility wave;
  doctrine: a silently skipped feature is a defect). A repo governed by a Ruff
  config with no `ruff` binary available (.venv or PATH) → the hook skips with
  a once-per-session notice to both Claude (`additionalContext`) and the user
  (`systemMessage`); a repo without a Ruff config stays quiet (the opt-out).
  `jq` absent → the whole hook skips visibly. Notice dedup state lives under
  `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, and Ruff, each with its absence behavior.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The toggle is now the `ruff_format_enabled` boolean (default `true`), read by
  the hook through the native `CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED` hook-process
  mirror. Configure interactively with `/plugin configure ruff-format` or headless via
  `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_RUFF_FORMAT_ENABLED` environment variable is retired and
  no longer read. A consumer that set it in a settings `env` block must re-express
  the value as the matching `userConfig` option. Zero-config
  behavior is unchanged (hook on, same defaults). The `HOOK_TELEMETRY_SINK` consumer-side
  telemetry seam is unaffected.
