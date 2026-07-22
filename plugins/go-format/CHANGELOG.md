# Changelog

All notable changes to the `go-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- **`statusMessage` declared on the hook's `hooks.json` handler** (hook-observability
  convention, `docs/conventions/hook-observability/`): a spinner label ("Formatting
  Go imports...") now shows while the hook runs. Config-only — no runtime behavior
  change.

## [0.1.1]

### Added

- Documented the generated-file guard's known limitation in
  `hooks/go-format.sh`: the leading-block scan is a deliberate string-match
  approximation of Go's own `ast.IsGenerated` (a parsed-AST classifier), the
  gap between the two is structural rather than a fixable bug, and no further
  pattern patches are planned unless a real-world generated file is observed
  defeating the scan — at which point the structural fix is a `go`-toolchain
  shell-out, not another pattern. Documentation-only; no behavior change.

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
