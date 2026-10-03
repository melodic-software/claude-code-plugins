# Changelog

All notable changes to the `docs-naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1] - 2026-10-02

### Changed

- **Shared `check-retirements.sh`, `config-root.sh` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's lib.**
  Each is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copies.

## [0.2.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5841](https://github.com/melodic-software/claude-code-plugins/issues/5841)).

## [0.1.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.1.3] - 2026-10-02

### Fixed

- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.

## [0.1.2] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.1.1] - 2026-10-01

### Changed

- Removed `reference/topic-docs.md` and its binding to the repository's topic-docs convention, which no longer exists. The audit's findings artifact lives in the memory slice, and the bundled config no longer exempts `docs/topics`.

## [0.1.0]

### Added

- **File-name skills.** `setup`, `audit-file-names`, `realign-file-names` and `generate-file-name-gate`
  moved here from the `docs-hygiene` plugin, with their scripts, templates, evals and reference docs.
- **Config files renamed.** The team layer is `.claude/docs-naming.json` and the personal overlay is
  `.claude/docs-naming.local.json`, with the schema unchanged. The old `.claude/docs-hygiene.json` and
  `.claude/docs-hygiene.local.json` are still read for one release with a warning, and `setup apply`
  refuses to write the team layer while the old name stands.
- **Memory directory and artifact type renamed** to `docs-naming`. A rename plan in flight under the
  old name needs a re-audit with `audit-file-names`.
