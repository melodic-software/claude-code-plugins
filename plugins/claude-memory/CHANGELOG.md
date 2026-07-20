# Changelog

All notable changes to the `claude-memory` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.2]

### Fixed

- **`orphan-rule-check` no longer truncates a quoted `memory_dir` at an interior `#`.**
  Seam resolution now routes through the shared `parse-concern-value.sh` helper
  (materialized from `lib/parse-concern-value.sh`), which resolves surrounding quotes
  *before* stripping comments: `memory_dir: ".scratch#dir"` keeps its `#` and the correct
  tier is excluded from the reference search, rather than collapsing to `.scratch` and
  masking an orphan rule. The naive `${seam%%#*}`-first strip is gone; unquoted trailing
  ` # comment`, whitespace, and trailing-slash handling are unchanged. As a
  non-interactive detector it still degrades to the documented `.work` default when the
  seam is unset — the contract's inferred/interactive rungs stay the calling skill's job.

## [0.2.1]

### Fixed

- **`orphan-rule-check` now resolves the excluded memory tier from the topic-docs seam**
  instead of hardcoding `.work/`. The reference search reads `memory_dir` from
  `.claude/topic-docs.yaml` (falling back to `.work/` when unset) and excludes that path,
  so a consumer that overrides `memory_dir` no longer has its real memory tier scanned —
  ephemeral files there can no longer register false references that mask an orphan rule.

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
