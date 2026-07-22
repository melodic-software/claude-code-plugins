# Changelog

All notable changes to the `go-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- Initial release: a `PostToolUse` hook that runs `goimports -w` on
  `Write`/`Edit` of a `.go` file — unconditionally, with no consumer-config
  opt-in gate (the one deliberate shape difference from the
  `ruff-format`/`typos-format` pattern; see issue #832's field survey).
  Skips files carrying Go's `// Code generated ... DO NOT EDIT.` marker.
  Syntax errors goimports can't parse surface via `additionalContext` as an
  advisory finding, never a tool break. Advisory only — never blocks the
  edit.
- `hook-telemetry` conformance: emits a schema-valid envelope
  (`docs/conventions/hook-telemetry/data/go-format.schema.json`) via the
  shared `hook::emit_telemetry` helper.
- `/go-format:setup check|apply` skill for prerequisite verification.
