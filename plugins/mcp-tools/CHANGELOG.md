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
  tool-search deferral exemption). Missing is at most an info advisory. The
  defect splits two ways: declared-but-ineffective (C17 over the ceiling or on
  an image-returning tool, C18 set to anything but JSON `true`) and
  declared-honored-but-unwarranted (C19 over-declared, spending session-start
  context deferral would have saved).
- A `meta-extraction` rule per SDK in `reference/server-discovery.md`, so
  C17-C19 have the extraction contract every other criterion already had:
  Python's `meta=` argument on `@mcp.tool`, the `_meta` field of the config
  object passed to TypeScript's `server.registerTool`, and .NET's repeatable
  `[McpMeta]` attribute. Each entry names how that language spells the JSON
  boolean `true` versus a string or a number, which is what C18's FAIL turns on.

### Changed

- C4's size budget now also covers the server `instructions` field — Claude
  Code truncates tool descriptions and server instructions at 2KB each.
  `discover.sh` emits per-tool records only, so Phase 2 gains a once-per-server
  step that resolves `instructions` from the server's construction site; without
  it the new clause would have had no input to audit. That construction site is
  usually not one of the discovered tool files, so the step searches the
  server's subtree and names the per-language spelling (`instructions=`,
  `ServerOptions.instructions`, `McpServerOptions.ServerInstructions`). A server
  declaring no `instructions` is recorded not applicable rather than passing;
  one whose construction site is out of scan scope is recorded undetermined.
- The OPINION authority row now states that C4 and C17-C19 draw their
  client-behavior facts from the Claude Code page — the tag stays OPINION
  because that page documents Claude Code's behavior rather than mandating the
  criterion, but the Source column no longer reads as if the facts were
  ungrounded.

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
