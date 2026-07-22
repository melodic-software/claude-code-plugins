# Changelog

All notable changes to the `ruff-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Fixed

- **Out-of-tree files are no longer processed when `CLAUDE_PROJECT_DIR` is
  unset.** The shared hook library's file-membership guard now falls back to
  git-working-tree containment when `CLAUDE_PROJECT_DIR` is unset (for example
  an autonomous session whose working directory is not a repository): a file
  under no git working tree is skipped, so a scratch or temporary file outside
  any repository is not processed with repo-scoped rules, while a repository
  file edited in such a session still is. Behavior when `CLAUDE_PROJECT_DIR`
  is set is unchanged.

## [0.5.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Formatting
  Python with Ruff...") now shows while the hook runs. Config-only — no runtime
  behavior change.

## [0.4.4]

### Documented

- Documented a known limitation of the pyproject.toml opt-in gate: the
  line-anchored `[tool.ruff]` header check does not recognize the equivalent
  TOML inline-table form (`[tool]` + `ruff = { ... }`), which Ruff itself
  honors. Such a repo is treated as un-configured and the hook skips — fails
  safe (a missed opt-in, never a wrong edit). Added a test case locking in the
  documented (skip) behavior. No gate logic change: a robust fix needs real
  TOML parsing, which is out of scope for this hook (see the hook's inline
  comment for the full rationale).

## [0.4.3]

### Fixed

- Published `data/ruff-format.schema.json` in the hook-telemetry convention and
  registered `ruff-format` in its Implementers table, closing the gap where the
  hook's `hook::emit_telemetry("ruff-format", ...)` envelope had no per-hook
  `data` schema for a consuming sink to validate against — unlike the sibling
  `markdown-format` and `typos-format` producers. No hook behavior change.

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
