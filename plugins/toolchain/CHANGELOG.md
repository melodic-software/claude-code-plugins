# Changelog

All notable changes to the `toolchain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` clarifies the
  contract's visibility mechanisms are consumer-repo root materializations outside the concern
  file's schema, and `/toolchain:setup` does not write them today (a setup-skill apply action is
  the contract's recorded follow-on).

## [0.2.0]

### Changed

- **BREAKING: `/toolchain:build` renamed to `/toolchain:check`.** The skill runs build + test + lint
  as a deterministic pass/fail gate, and per the marketplace naming grammar `check` = gate; "build"
  is also a null phase for several covered ecosystems (Python, Markdown). The skill directory,
  frontmatter `name`, and every repo-wide reference move together; no `renames`-map entry is added
  (clean breaking change while the marketplace is settling). Invoke `/toolchain:check` where you
  previously invoked `/toolchain:build`; behavior, arguments, and the resolution ladder are unchanged.

## [0.1.1]

### Fixed

- **`/toolchain:setup` reports `vault_backend: gitbook` as deferred and non-writable.** Offering
  or preserving the key now cites the ADR
  (`docs/adr/0001-defer-gitbook-as-knowledge-vault-backend.md`) and states that durable writes still
  target `docs`; the skill never configures or tests a GitBook API, MCP, or Git Sync writer.

## [0.1.0]

### Added

- Initial release — three skills extracted from the `implementation` plugin (skill names unchanged):
  `/toolchain:build` (polyglot build + test + lint for changed files, resolved through the four-rung
  ecosystem-commands ladder), `/toolchain:lint` (lint + format only, plus the `yaml` and `cross-cutting`
  surfaces), and `/toolchain:setup` (re-runnable writer of the tracked `.claude/ecosystems/*.yaml`
  command config and the offered `.claude/topic-docs.yaml` concern file).
- Bundled reference: the resolution ladder, the schema-conformant per-ecosystem portable defaults under
  `reference/ecosystems/`, and the plugin-local `reference/topic-docs.md` binding that `/toolchain:setup`
  reads to offer the topic-docs concern file.
- Cross-plugin references to the `verification` plugin's `/verification:confirm` are informational and
  degrade gracefully — this plugin never hard-depends on any other plugin.
