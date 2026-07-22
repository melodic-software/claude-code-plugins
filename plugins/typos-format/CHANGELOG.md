# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Changed

- Sync of the shared `hook-utils.sh`: the git-option parser distinguishes `--config-env`
  (an env-var name) from `-c`/`--config` (an inline value), and a `--config-env` alias for
  a guarded subcommand is refused by shape rather than by resolving the environment
  variable's value (`#740`). No behavior change for this plugin — it does not inspect git
  config values; shipped so consumers receive the shared library update.

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
