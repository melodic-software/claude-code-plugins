# Changelog

All notable changes to the `go-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- Initial release: a `PostToolUse` hook that runs `gofmt -w` unconditionally on every `Write`/`Edit`
  of a `.go` file. gofmt has no configuration surface, so there is no consumer opt-in to gate on —
  matching the sibling `typos-format` hook's unconditional pattern. A syntax error (gofmt cannot
  parse the file) leaves it byte-for-byte untouched and surfaces the diagnostic via
  `additionalContext` instead of writing anything.
- `/go-format:setup` skill: `check` (read-only) reports Bash, `jq`, and the gofmt binary
  (resolved exactly as the hook resolves it — PATH only), plus the `go_format_enabled` toggle;
  `apply` is guidance-only (gofmt ships with the Go toolchain, never installed on its own).
- `go_format_enabled` `userConfig` kill switch (default `true`).
- Hook-telemetry envelope producer (`hook` value `go-format`), schema published at
  `docs/conventions/hook-telemetry/data/go-format.schema.json`.
