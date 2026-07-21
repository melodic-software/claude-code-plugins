# Changelog

All notable changes to the `typos-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Removed the opt-in config-gate.** The hook now runs `typos --write-changes`
  unconditionally on every edited file, matching `markdown-format`'s
  unconditional pattern instead of `ruff-format`'s config-gated one. typos
  ships a built-in spelling dictionary and runs with zero configuration; the
  ancestor walk-up looking for a governing `typos.toml`/`_typos.toml`/
  `.typos.toml`/`Cargo.toml`/`pyproject.toml` was only ever an activation
  switch the hook implemented itself — it made the hook a silent no-op on any
  repo without a hand-authored typos config, defeating the plugin's
  zero-config auto-fix purpose. typos' own config discovery is unaffected: a
  governing config, when present, is still found and honored by typos itself
  (for allowlist/exclude purposes) — the hook just no longer gates activation
  on one existing. This is a behavior change for existing installs — a repo
  with no typos config now has its files actively rewritten on edit instead
  of being left untouched — hence the minor version bump.

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
