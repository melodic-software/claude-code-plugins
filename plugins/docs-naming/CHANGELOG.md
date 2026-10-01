# Changelog

All notable changes to the `docs-naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
