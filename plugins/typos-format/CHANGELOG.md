# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.1]

### Fixed

- **Out-of-tree files are no longer processed when `CLAUDE_PROJECT_DIR` is
  unset.** The shared hook library's file-membership guard now falls back to
  git-working-tree containment when `CLAUDE_PROJECT_DIR` is unset (for example
  an autonomous session whose working directory is not a repository): a file
  under no git working tree is skipped, so a scratch or temporary file outside
  any repository is not processed with repo-scoped rules, while a repository
  file edited in such a session still is. Behavior when `CLAUDE_PROJECT_DIR`
  is set is unchanged.

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
