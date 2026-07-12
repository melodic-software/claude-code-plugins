# Changelog

All notable changes to the `implementation` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Consume the ecosystem-commands contract.** The two divergent per-ecosystem reference tables
  (`skills/build/reference/ecosystem-config.md` and `skills/lint/reference/ecosystem-config.md`) are
  replaced by ONE bundled, schema-conformant set of portable-default files at
  `reference/ecosystems/<ecosystem>.yaml`, validated against the contract's `ecosystem.schema.json`
  (`docs/conventions/ecosystem-commands/README.md`). Both `/build` and `/lint` now read the one
  location.
- **Ladder resolution in `/build` and `/lint`.** Each ecosystem's command surface resolves through the
  contract's four-rung ladder (shared doc: `reference/resolution-ladder.md`): consumer
  `.claude/ecosystems/<ecosystem>.yaml` (additive over a `~/.claude/ecosystems/` user-global base and a
  `.local.yaml` overlay) → inference → ask → bundled portable defaults. A malformed consumer file warns
  and degrades to inference, never a hard stop. Bundled defaults are the rung-4 fallback only, never
  written into a consumer repo outside setup or a persisted inference.
- **Unified command keys.** The old build-table `lint-cmd` and lint-table `check-cmd` were the same
  verb; they collapse to the contract's `check-cmd`. Command keys are now `build-cmd`, `test-cmd`,
  `check-cmd`, `fix-cmd`.

### Added

- **`/implementation:setup`** — re-runnable skill that interviews, infers, and writes the consuming
  repo's tracked `.claude/ecosystems/*.yaml`, the ladder's writer for the infer/ask rungs.

### Design decisions (from the wave-2 design gate; recorded, not reopened)

- **Data unified, scope preserved.** Unifying the tables into one 8-ecosystem set would have pulled the
  lint-only `yaml` and `cross-cutting` surfaces into `/build` — and `cross-cutting`'s `**` glob matches
  every change. Per the contract's canonical-verb-vs-context-binding split, the *data* is unified while
  each skill keeps its *scope* (binding is per-surface): `/build` covers
  dotnet/python/typescript/bash/powershell/markdown; `yaml` and `cross-cutting` remain `/lint`-only.
- **Reconciled divergences.** Where the two old tables disagreed, the contract's worked examples are the
  authority: dropped the lint-table's `$REPO_ROOT/`-prefixed dotnet command in favor of the contract's
  `<solution-or-project-file>` form (the running skill resolves absolute paths).
- **Config home is concern-named** `.claude/ecosystems/` (a recorded precedent-extension of the
  extensibility-contract seam, since more than one plugin consumes it). No new `userConfig` knob — the
  path is conventional, not declared. Task-runner deferred — command values stay opaque strings.

## [0.1.0]

- Initial release: ten skills — `implement`, `implement-dispatch`, `build`, `lint`, `test-write`,
  `test-plan`, `test-diagnose`, `test-e2e`, `verify-changes`, `verify-improvement`.
