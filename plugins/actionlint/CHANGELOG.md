# Changelog

All notable changes to the `actionlint` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Checking
  workflow with actionlint...") now shows while the hook runs. Config-only — no
  runtime behavior change.

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

- **`/actionlint:setup` skill** (fleet conformance wave: a uniform check-centric
  setup contract across the hook plugins). `check` (default) is read-only — it
  reads the hook script as the single source of truth and probes each runtime
  prerequisite (Bash, `jq`, `actionlint`), the optional auto-discovered
  `.github/actionlint.yaml`, and the effective `actionlint_enabled` toggle,
  reporting a PASS/FAIL/INFO table with one remediation line per FAIL. `apply`
  re-runs `check` then points at the resolution for each finding. Every
  prerequisite is a `PATH` binary or the native toggle, so `apply` is
  guidance-only with no write path — it never installs packages and never
  modifies the repository, user settings, or the plugin cache.

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

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
