# Changelog

All notable changes to the `ruff-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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

- **`/ruff-format:setup` skill** (fleet conformance wave, dim 8). A uniform check-centric
  setup contract: `check` (default, read-only) reads the hook as the single source of truth
  and reports a PASS/FAIL/INFO table for Bash, `jq`, the Ruff binary (resolved exactly as the
  hook resolves it), the governing Ruff config opt-in, and the `ruff_format_enabled` toggle.
  `apply` is idempotent and guidance-first: it re-runs `check`, points at system-tool
  remediations, and the one write path — `apply install-ruff` — installs Ruff only into a
  managed environment the repo already uses (an existing `.venv` via its own pip/uv; a
  uv/Poetry project gets that tool's add command as guidance), never creating a virtual
  environment or installing globally, and re-verifies the binary probe after the install
  rather than trusting its exit code.

## [0.3.1]

### Changed

- Shared `hook-utils.sh` resynced from the repository library (no behavior
  change in this plugin's hook).

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
