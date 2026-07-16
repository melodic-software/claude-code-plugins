# Changelog

All notable changes to the `toolchain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
