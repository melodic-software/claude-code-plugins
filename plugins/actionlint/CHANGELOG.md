# Changelog

All notable changes to the `actionlint` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Changed

- **Missing prerequisites now skip visibly** (prerequisite-visibility wave;
  doctrine: a silently skipped feature is a defect). When `actionlint` or `jq`
  is absent, the hook emits a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`) instead of a silent
  no-op, then still exits `0` (advisory, never blocking). Notice dedup state
  lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, and `actionlint`, each with its absence behavior.

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
