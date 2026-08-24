# mcp-tools

A Claude Code plugin that audits your MCP server's tool definitions against design-quality criteria and
returns a per-tool PASS/WARN/FAIL scorecard. It **reports**; it never edits your tool source.

The criteria come from three upstream authorities, cited so the current text always governs:

- [MCP specification 2025-11-25 — Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Claude Code — Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp)

## What it checks

19 criteria (C1-C19) across seven categories, each tagged by authority (SPEC-MUST / SPEC-SHOULD /
SPEC-OPTIONAL / ANTHROPIC / OPINION) so you can tell a protocol requirement from a style preference.
OPINION is the skill's own judgment, including the criteria built on Claude-Code-specific client
behavior, which the Claude Code page documents rather than mandates:

- **Description**. States what / when / returns, fits the client size budget (2KB in Claude Code, for tool descriptions and server instructions alike), leaks no implementation detail.
- **Parameters**. Every parameter described, guidance and format examples, documented optional defaults.
- **Naming**. Valid name charset/length (spec), outcome-driven, service-namespaced.
- **Annotations**. `readOnlyHint`, `destructiveHint`, `idempotentHint`. These are OPTIONAL in the spec, so a missing annotation is WARN, never FAIL.
- **Granularity**. Workflow-shaped consolidation, not one tool per raw API call.
- **Schema**. Callable from the schema alone, with a valid `inputSchema`.
- **Claude Code `_meta` annotations**. `anthropic/maxResultSizeChars`, `anthropic/requiresUserInteraction`, `anthropic/alwaysLoad`. Missing is at most an info advisory; a declared value Claude Code ignores or caps is the defect.

Language-agnostic: it discovers tools in Python (`mcp`), TypeScript (`@modelcontextprotocol/sdk`), and
.NET (`ModelContextProtocol`) by the SDKs' own tool markers.

## Usage

```shell
/mcp-tools:audit            # audit every MCP tool in the project
/mcp-tools:audit <dir>      # scope the audit to one server's directory
```

Claude can also invoke it automatically when you ask to "audit MCP tools" or "check MCP tool descriptions".

## What it does NOT do

- Does not modify tool definitions. It reports; you apply the fixes.
- Does not test tool functionality. Use the MCP Inspector for that.
- Does not evaluate MCP resources. Only tools.

## Requirements

- **Bash + coreutils** for the audit's inline mechanics. On native Windows,
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

This plugin has no `userConfig`. It reads your project's tool source directly and writes nothing. The
scorecard is returned in the response.

## License

MIT (SPDX-License-Identifier: MIT).
