# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.2]

### Added

- **`hook::jq_fields` in the shared hook lib (#1345).** Extracts N jq fields in ONE `jq` process
  instead of N `printf | jq | tr` pipelines, returning them in `HOOK_JQ_FIELDS`. Values are joined on
  U+001E, which jq strips from each value first so payload text can never shift field alignment. This
  plugin's own hooks do not call it yet; it arrives with the shared-lib sync.

### Fixed

- **Two process spawns removed from every hook invocation (#1345).** `hook::buffer_stdin` stripped CR
  with `$(printf '%s' "$input" | tr -d '\r')`; it now uses parameter expansion. On Windows, where
  `fork` emulation makes each spawn cost hundreds of milliseconds, that command substitution was the
  largest fixed cost paid by every hook in this plugin on every matching tool call. The buffered
  payload — including the trailing-newline trim a command substitution performed implicitly — is
  byte-identical. Carried in via `scripts/sync-hook-utils.sh`; no behavior of this plugin changed.

## [0.3.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

## [0.3.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Fixing
  typos...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.2.0]

### Changed

- **Removed the opt-in config-gate.** The hook now runs `typos --write-changes`
  unconditionally on every `Write`/`Edit`, matching `markdown-format`'s existing
  unconditional pattern — typos ships a built-in spelling dictionary and needs
  no configuration to be useful. Previously the hook silently no-op'd on any
  repo without a hand-authored `typos.toml`/`_typos.toml`/`.typos.toml`/
  `Cargo.toml`/`pyproject.toml`, defeating the plugin's zero-config auto-fix
  purpose on exactly the repos it was meant to help. A consumer typos config,
  when present, is still discovered and honored automatically by typos itself
  (allowlist/exclude) — this hook never re-implemented that discovery and
  still doesn't; only the activation gate is removed.

## [0.1.0]

### Added

- Initial release: a `PostToolUse` hook that runs `typos --write-changes` on
  `Write`/`Edit` of any file, gated on a consumer typos config
  (`typos.toml`/`_typos.toml`/`.typos.toml`/`Cargo.toml`/`pyproject.toml`)
  found by an ancestor walk-up, mirroring the `ruff-format`/`markdown-format`
  plugin pattern. Residual (unfixable) findings surface via `additionalContext`
  with remediation guidance pointing at `extend-words` / `extend-identifiers` /
  `extend-ignore-re` allowlist entries. Advisory only — never blocks the edit.
- `hook-telemetry` conformance: emits a schema-valid envelope
  (`docs/conventions/hook-telemetry/data/typos-format.schema.json`) via the
  shared `hook::emit_telemetry` helper.
- `/typos-format:setup check|apply` skill for prerequisite verification.
