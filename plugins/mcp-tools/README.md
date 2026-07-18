# mcp-tools

A Claude Code plugin that audits your MCP server's tool definitions against design-quality criteria and
returns a per-tool PASS/WARN/FAIL scorecard. It **reports**; it never edits your tool source.

The criteria come from two upstream authorities, cited so the current text always governs:

- [MCP specification 2025-11-25 — Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)

## What it checks

16 criteria (C1-C16) across six categories, each tagged by authority (SPEC-MUST / SPEC-SHOULD /
SPEC-OPTIONAL / ANTHROPIC / OPINION) so you can tell a protocol requirement from a style preference:

- **Description** — states what / when / returns, fits the client size budget, leaks no implementation detail.
- **Parameters** — every parameter described, guidance and format examples, documented optional defaults.
- **Naming** — valid name charset/length (spec), outcome-driven, service-namespaced.
- **Annotations** — `readOnlyHint`, `destructiveHint`, `idempotentHint`. These are OPTIONAL in the spec, so a missing annotation is WARN, never FAIL.
- **Granularity** — workflow-shaped consolidation, not one tool per raw API call.
- **Schema** — callable from the schema alone, with a valid `inputSchema`.

Language-agnostic: it discovers tools in Python (FastMCP), TypeScript (`@modelcontextprotocol/sdk`), and
.NET (`ModelContextProtocol`) by the SDKs' own tool markers.

## Usage

```shell
/mcp-tools:audit            # audit every MCP tool in the project
/mcp-tools:audit <dir>      # scope the audit to one server's directory
```

Claude can also invoke it automatically when you ask to "audit MCP tools" or "check MCP tool descriptions".

## What it does NOT do

- Does not modify tool definitions — it reports; you apply the fixes.
- Does not test tool functionality — use the MCP Inspector for that.
- Does not evaluate MCP resources — only tools.

## Requirements

- **Bash + coreutils** for the audit's inline mechanics — on native Windows,
  install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)
  so they run under Git Bash.
- **jq** on `PATH` for JSON handling
  ([install](https://jqlang.org/download/); a separate install in Git Bash).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install mcp-tools@melodic-software
```

## Configuration

This plugin has no `userConfig`. It reads your project's tool source directly and writes nothing — the
scorecard is returned in the response.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
