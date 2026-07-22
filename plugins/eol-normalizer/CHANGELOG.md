# Changelog

All notable changes to the `eol-normalizer` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Normalizing
  line endings...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.4.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.4.1]

### Changed

- Hook stdin is read via the shared `hook::buffer_stdin` helper (bounded `read -t`,
  default 2s) instead of a bare `cat`, so a Windows Win32-pipe late-EOF stall can no
  longer hang the hook indefinitely. Empty or timed-out stdin exits as a skip, matching
  the existing empty-payload behavior.

## [0.4.0]

### Added

- **`/eol-normalizer:setup` skill** (fleet conformance wave, dim 8). A uniform check-centric
  setup contract: `check` (default, read-only) reads both the hook and its sourced
  `normalize-eol.sh` library as the single source of truth and reports a PASS/FAIL/INFO table
  for Bash, `jq`, `git` (FAIL when absent — the hook silently no-ops without it, so the check
  is the only visibility), the governing `.gitattributes` `eol=` policy, and the
  `eol_normalizer_enabled` toggle. `apply` is idempotent and pure guidance — every
  prerequisite is a system tool, so it installs nothing and writes nothing (never
  `.gitattributes`).

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

## [0.3.0]

### Changed

- **Missing jq now skips visibly** (prerequisite-visibility wave; doctrine: a
  silently skipped feature is a defect). Without `jq` the hook cannot parse its
  input, so it now surfaces a once-per-session notice to both Claude
  (`additionalContext`) and the user (`systemMessage`) instead of silently
  disabling normalization. Notice dedup state lives under
  `${CLAUDE_PLUGIN_DATA}/skip-notices`.
- Shared `hook-utils.sh` resynced with the new prerequisite-visibility helpers
  (jq-free notice emitters, once-per-session gate, jq gate).
- README now declares the full hook runtime: Bash (Git Bash on native Windows),
  `jq`, and git, with the no-git-repo case classified as a quiet not-applicable
  rather than a missing prerequisite.

## [0.2.0]

### Changed

- **Kill switch migrated to native `userConfig`** (the fleet-wide kill-switch doctrine
  ruling). The hook's toggle is now the `eol_normalizer_enabled` boolean (default `true`),
  read by the hook through the native `CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED`
  hook-process mirror. Configure interactively with `/plugin configure eol-normalizer`
  or headless via `claude plugin install --config KEY=VALUE`.
- **BREAKING:** the `HOOK_EOL_NORMALIZER_ENABLED` environment variable is retired
  and no longer read. A consumer that set it in a settings `env` block must
  re-express the value as the matching `userConfig` option.
  Zero-config behavior is unchanged (normalization on, same defaults). The
  `HOOK_TELEMETRY_SINK` consumer-side telemetry seam is unaffected.
