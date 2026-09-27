# mcp-tools

A Claude Code plugin with two MCP audits. Both **report**; neither edits your code or configuration.

- **`/mcp-tools:audit`** is the author-side audit. It reads the tool definitions of an MCP server
  you build and returns a per-tool PASS/WARN/FAIL design-quality scorecard.
- **`/mcp-tools:audit-posture`** is the consumer-side audit. It inventories the MCP servers your
  Claude Code configuration launches or connects to and reports whether each is safe to run:
  floating versions, publisher provenance, local stdio where a remote endpoint exists, and OCI
  images available but unused.

## Design-quality audit

The criteria come from three upstream authorities, cited so the current text always governs:

- [MCP specification 2025-11-25: Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [Anthropic: Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Claude Code: Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp)

19 criteria (C1-C19) across seven categories, each tagged by authority (SPEC-MUST / SPEC-SHOULD /
SPEC-OPTIONAL / ANTHROPIC / OPINION) so you can tell a protocol requirement from a style preference.
OPINION is the skill's own judgment, including the criteria built on Claude-Code-specific client
behavior, which the Claude Code page documents rather than mandates:

- **Description**. States what / when / returns, fits the skill's own 2KB budget for tool descriptions and server instructions alike, leaks no implementation detail.
- **Parameters**. Every parameter described, guidance and format examples, documented optional defaults.
- **Naming**. Valid name charset/length (spec), outcome-driven, service-namespaced.
- **Annotations**. `readOnlyHint`, `destructiveHint`, `idempotentHint`. These are OPTIONAL in the spec, so a missing annotation is WARN, never FAIL.
- **Granularity**. Workflow-shaped consolidation, not one tool per raw API call.
- **Schema**. Callable from the schema alone, with a valid `inputSchema`.
- **Claude Code `_meta` annotations**. `anthropic/maxResultSizeChars`, `anthropic/requiresUserInteraction`, `anthropic/alwaysLoad`. Missing is at most an info advisory; a declared value Claude Code ignores or caps is the defect.

Language-agnostic: it discovers tools in Python (`mcp`), TypeScript (`@modelcontextprotocol/sdk`), and
.NET (`ModelContextProtocol`) by the SDKs' own tool markers.

## Supply-chain posture audit

A bundled script reads the MCP configuration Claude Code resolves (user and local scope in
`~/.claude.json`, the project `.mcp.json`, managed `managed-mcp.json` and `managedMcpServers`, and
any file you pass) and emits a dated inventory: scope, whether the entry is effective, transport,
launcher, package, pin state, publisher, and whether it runs in the Claude Code sandbox (a stdio
server does not). The skill then evaluates five criteria:

- **P1 Floating version**. An `npx`, `uvx`, or similar launcher with no version or `@latest` is a
  FAIL: it runs whatever the registry serves when the server starts.
- **P2 Local stdio where the vendor offers a remote endpoint**. A remote endpoint runs no code on
  your host.
- **P3 Publisher provenance**. A package named for a vendor but not published by it.
- **P4 OCI image available but unused**.
- **P5 Inventory**. The dated table itself, meant to be saved and diffed between runs.

P2 to P4 need facts the config does not hold, so their results are labeled `unverified` unless you
ask for a registry or vendor lookup.

## Usage

```shell
/mcp-tools:audit                                       # audit every MCP tool in the project
/mcp-tools:audit <dir>                                 # scope the audit to one server's directory
/mcp-tools:audit-posture                               # audit the servers in your Claude Code config
/mcp-tools:audit-posture --config <plugin>/.mcp.json   # include a plugin's servers
```

Claude can also invoke them when you ask to "audit MCP tools" or "is it safe to run my MCP servers".

## What it does NOT do

- Does not modify tool definitions or configuration. It reports; you apply the fixes.
- Does not run, install, or connect to any MCP server. The posture audit reads config files only.
- Does not print `env` or `headers` values from your configuration.
- Does not test tool functionality. Use the MCP Inspector for that.
- Does not evaluate MCP resources. Only tools.
- Does not check whether MCP configuration is correct or enabled. `/claude-config:audit` does that.

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

This plugin has no `userConfig`. The design-quality audit reads your project's tool source; the
posture audit reads your MCP configuration through its script. Neither writes anything; results are
returned in the response.

## License

MIT (SPDX-License-Identifier: MIT).
