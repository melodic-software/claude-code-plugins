# Changelog

All notable changes to the `biome-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Added

- **`/biome-format:setup` skill** (fleet conformance wave, dim 8). A uniform check-centric
  setup contract: `check` (default, read-only) reads the hook as the single source of truth
  and reports a PASS/FAIL/INFO table for Bash, `jq`, the Biome binary (resolved exactly as
  the hook resolves it), the governing Biome config opt-in, and the `biome_format_enabled`
  toggle. `apply` is idempotent and guidance-first: it re-runs `check`, points at system-tool
  remediations, and the one write path — `apply install-biome` — adds `@biomejs/biome` as a
  dev dependency using the repository's own package manager, re-verifying the binary probe
  after the install rather than trusting its exit code.

## [0.3.0]

### Changed

- **Missing prerequisites now skip visibly** (prerequisite-visibility wave;
  doctrine: a silently skipped feature is a defect). A repo governed by a Biome
  config with no `biome` binary available (node_modules/.bin or PATH) → the
  hook skips with a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`); a repo without a Biome
  config stays quiet (the opt-out). `jq` absent → the whole hook skips visibly.
  Notice dedup state lives under `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, and Biome, each with its absence behavior.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch
  doctrine ruling). The hook's toggle is now the `biome_format_enabled` boolean
  (default `true`), read through the native `CLAUDE_PLUGIN_OPTION_<KEY>`
  hook-process mirror. Configure interactively with `/plugin configure biome-format`
  or headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_BIOME_FORMAT_ENABLED` environment variable is retired
  and no longer read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option. Zero-config behavior is unchanged (hook on, same
  defaults). The `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is
  unaffected.
