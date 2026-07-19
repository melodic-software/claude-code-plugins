# Changelog

All notable changes to the `claude-memory` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **BREAKING — the `health` skill renamed to `audit`** (fleet conformance wave, naming grammar):
  `/claude-memory:health` → `/claude-memory:audit`. The old invocation stops resolving; update any
  saved references. Actions (`audit` / `fix` / `update` / `report`) are unchanged.

## [0.1.0]

### Added

- Initial release. The `health` skill was extracted from the `claude-config-audit` plugin — where it
  shipped as the `memory-health` skill — into this standalone plugin, invoked as `/claude-memory:health`.
  It audits the Claude Code instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`,
  and auto-memory) against a checklist derived from official Claude Code documentation, with a
  deterministic script-backed spine (MEMORY.md index integrity, orphan always-loaded rules) and
  `audit` / `fix` / `update` / `report` actions. Audit reports stay contributor-local in the plugin's
  data directory.
