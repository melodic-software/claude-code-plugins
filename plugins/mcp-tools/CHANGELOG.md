# Changelog

All notable changes to the `mcp-tools` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.3]

### Added

- Checklist section 7 (C17-C19): the Claude-Code-specific `_meta` annotations
  documented on the Claude Code MCP page — `anthropic/maxResultSizeChars`
  (per-tool result-size ceiling, hard-capped at 500,000 characters),
  `anthropic/requiresUserInteraction` (per-call consent prompt; JSON boolean
  `true` only; Claude Code v2.1.199+), and `anthropic/alwaysLoad` (per-tool
  tool-search deferral exemption). Missing is at most an info advisory; a
  declared value Claude Code ignores or caps is the defect case.

### Changed

- C4's size budget now also covers the server `instructions` field — Claude
  Code truncates tool descriptions and server instructions at 2KB each.
  `discover.sh` emits per-tool records only, so Phase 2 gains a once-per-server
  step that resolves `instructions` from the server's construction site; without
  it the new clause would have had no input to audit. A server declaring no
  `instructions` is recorded not applicable rather than passing.

## [0.2.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.1]

### Changed

- README gains a Requirements section declaring the audit's Bash + coreutils
  and `jq` mechanics with their Windows path (Git Bash; `jq` is a separate
  install there) — cross-platform declaration wave.

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/mcp-tools/` for earlier changes.
